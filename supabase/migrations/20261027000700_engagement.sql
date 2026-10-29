-- 0007 — Engagement domain: collections, interactions, viewings, inquiries, notifications.

set search_path = public, extensions;

create table if not exists public.collections (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references public.profiles(id) on delete cascade,
  name       text not null check (char_length(trim(name)) between 1 and 80),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists collections_client_idx on public.collections (client_id, created_at desc);
create unique index if not exists collections_one_default_idx
  on public.collections (client_id) where is_default;

create table if not exists public.collection_items (
  collection_id uuid not null references public.collections(id) on delete cascade,
  property_id   uuid not null references public.properties(id) on delete cascade,
  note          text,
  added_at      timestamptz not null default now(),
  primary key (collection_id, property_id)
);

create index if not exists collection_items_property_idx on public.collection_items (property_id);

create table if not exists public.property_interactions (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid not null references public.profiles(id) on delete cascade,
  property_id     uuid not null references public.properties(id) on delete cascade,
  interaction_type public.interaction_type not null,
  session_id      text,
  dwell_seconds   integer check (dwell_seconds >= 0),
  occurred_at     timestamptz not null default now()
);

create index if not exists property_interactions_client_idx
  on public.property_interactions (client_id, occurred_at desc);
create index if not exists property_interactions_property_idx
  on public.property_interactions (property_id, occurred_at desc);
create index if not exists property_interactions_purge_idx
  on public.property_interactions (occurred_at);

create table if not exists public.agent_availability (
  id         uuid primary key default gen_random_uuid(),
  agent_id   uuid not null references public.profiles(id) on delete cascade,
  weekday    smallint not null check (weekday between 0 and 6),
  start_time time not null,
  end_time   time not null,
  created_at timestamptz not null default now(),
  constraint availability_order check (start_time < end_time)
);

create index if not exists agent_availability_agent_idx on public.agent_availability (agent_id, weekday);

-- Two windows for the same agent/day may not overlap.
create or replace function public.check_availability_overlap()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if exists (
    select 1 from public.agent_availability a
    where a.agent_id = new.agent_id
      and a.weekday = new.weekday
      and a.id <> coalesce(new.id, gen_random_uuid())
      and new.start_time < a.end_time
      and new.end_time > a.start_time
  ) then
    raise exception 'availability window overlaps an existing window' using errcode = '23P01';
  end if;
  return new;
end;
$$;

drop trigger if exists agent_availability_no_overlap on public.agent_availability;
create trigger agent_availability_no_overlap
  before insert or update on public.agent_availability
  for each row execute function public.check_availability_overlap();

create table if not exists public.viewing_requests (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid not null references public.profiles(id) on delete cascade,
  property_id      uuid not null,
  -- Deliberate exception 1 (documented): agent_id is denormalised from the
  -- listing so the composite FK and the exclusion constraint can exist.
  agent_id         uuid not null,
  requested_start  timestamptz not null,
  duration_minutes smallint not null default 45 check (duration_minutes between 15 and 240),
  -- Deliberate exception 2 (documented): ends_at is a generated column, so the
  -- database — not the application — guarantees start + duration.
  ends_at          timestamptz generated always as (
                     requested_start + (duration_minutes * interval '1 minute')
                   ) stored,
  status           public.viewing_status not null default 'requested',
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint viewing_requests_property_agent_fk
    foreign key (property_id, agent_id)
    references public.properties(id, agent_id) on delete cascade,
  -- No two live viewings for the same agent may overlap in time.
  constraint viewing_requests_no_overlap
    exclude using gist (
      agent_id with =,
      tstzrange(requested_start, ends_at) with &&
    ) where (status in ('requested', 'confirmed'))
);

create index if not exists viewing_requests_client_idx
  on public.viewing_requests (client_id, requested_start desc);
create index if not exists viewing_requests_agent_idx
  on public.viewing_requests (agent_id, requested_start);
create index if not exists viewing_requests_property_idx on public.viewing_requests (property_id);

create table if not exists public.inquiries (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.profiles(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  subject     text not null,
  status      public.inquiry_status not null default 'open',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  closed_at   timestamptz,
  constraint inquiry_closed_at check (
    (status = 'open' and closed_at is null) or (status = 'closed' and closed_at is not null)
  )
);

create index if not exists inquiries_client_idx on public.inquiries (client_id, updated_at desc);
create index if not exists inquiries_property_idx on public.inquiries (property_id);

create table if not exists public.inquiry_messages (
  id         uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (char_length(trim(body)) > 0),
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists inquiry_messages_inquiry_idx
  on public.inquiry_messages (inquiry_id, created_at);

create table if not exists public.notifications (
  id                 uuid primary key default gen_random_uuid(),
  recipient_id       uuid not null references public.profiles(id) on delete cascade,
  type               text not null check (type in (
                       'viewing_requested', 'viewing_confirmed', 'viewing_declined',
                       'viewing_cancelled', 'inquiry_reply', 'price_drop', 'system'
                     )),
  property_id        uuid references public.properties(id) on delete cascade,
  viewing_request_id uuid references public.viewing_requests(id) on delete cascade,
  inquiry_id         uuid references public.inquiries(id) on delete cascade,
  body               text not null default '',
  read_at            timestamptz,
  created_at         timestamptz not null default now(),
  -- Exactly one subject reference, enforced by the database.
  constraint notifications_one_subject check (
    num_nonnulls(property_id, viewing_request_id, inquiry_id) = 1
  )
);

create index if not exists notifications_recipient_idx
  on public.notifications (recipient_id, created_at desc);
create index if not exists notifications_unread_idx
  on public.notifications (recipient_id) where read_at is null;

create or replace trigger collections_touch_updated_at
  before update on public.collections
  for each row execute function public.set_updated_at();

create or replace trigger viewing_requests_touch_updated_at
  before update on public.viewing_requests
  for each row execute function public.set_updated_at();

create or replace trigger inquiries_touch_updated_at
  before update on public.inquiries
  for each row execute function public.set_updated_at();

-- ── Notifications written by the database, not the client ──────────────────
create or replace function public.notify_viewing_change()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_type text;
  v_recipient uuid;
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (recipient_id, type, viewing_request_id, body)
    values (new.agent_id, 'viewing_requested', new.id,
            'A client requested a viewing for ' || to_char(new.requested_start, 'DD Mon YYYY HH24:MI'));
    return new;
  end if;

  if new.status is distinct from old.status then
    v_type := case new.status
      when 'confirmed' then 'viewing_confirmed'
      when 'declined' then 'viewing_declined'
      when 'cancelled' then 'viewing_cancelled'
      else null
    end;
    if v_type is not null then
      v_recipient := case when new.status = 'cancelled' then new.agent_id else new.client_id end;
      insert into public.notifications (recipient_id, type, viewing_request_id, body)
      values (v_recipient, v_type, new.id,
              'Viewing ' || new.status::text || ' for ' || to_char(new.requested_start, 'DD Mon YYYY HH24:MI'));
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists viewing_requests_notify on public.viewing_requests;
create trigger viewing_requests_notify
  after insert or update on public.viewing_requests
  for each row execute function public.notify_viewing_change();

create or replace function public.notify_inquiry_reply()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_inquiry public.inquiries%rowtype;
  v_agent uuid;
  v_recipient uuid;
begin
  select * into v_inquiry from public.inquiries where id = new.inquiry_id;
  if v_inquiry.id is null then return new; end if;

  select p.agent_id into v_agent from public.properties p where p.id = v_inquiry.property_id;
  v_recipient := case when new.sender_id = v_inquiry.client_id then v_agent else v_inquiry.client_id end;

  if v_recipient is not null and v_recipient <> new.sender_id then
    insert into public.notifications (recipient_id, type, inquiry_id, body)
    values (v_recipient, 'inquiry_reply', v_inquiry.id, left(new.body, 140));
  end if;

  update public.inquiries set updated_at = now() where id = v_inquiry.id;
  return new;
end;
$$;

drop trigger if exists inquiry_messages_notify on public.inquiry_messages;
create trigger inquiry_messages_notify
  after insert on public.inquiry_messages
  for each row execute function public.notify_inquiry_reply();

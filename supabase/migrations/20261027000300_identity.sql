-- 0003 — Identity and trust domain.

set search_path = public, extensions;

create table if not exists public.agencies (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  license_number text not null unique,
  city_id        uuid references public.cities(id) on delete set null,
  contact_email  text not null,
  phone          text,
  created_at     timestamptz not null default now()
);

create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  role          public.user_role not null default 'client',
  agency_id     uuid references public.agencies(id) on delete set null,
  full_name     text not null default '',
  phone         text,
  avatar_path   text,
  is_anonymous  boolean not null default false,
  locale        text not null default 'en' check (locale in ('en', 'ar')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists profiles_role_idx on public.profiles (role);
create index if not exists profiles_agency_idx on public.profiles (agency_id);

create table if not exists public.agent_profiles (
  profile_id            uuid primary key references public.profiles(id) on delete cascade,
  display_title         text,
  bio                   text,
  professional_license_no text,
  years_experience      smallint check (years_experience between 0 and 80),
  public_phone          text,
  is_accepting_viewings boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table if not exists public.agency_verifications (
  id            uuid primary key default gen_random_uuid(),
  agency_id     uuid not null references public.agencies(id) on delete cascade,
  submitted_by  uuid not null references public.profiles(id) on delete cascade,
  document_path text not null,
  status        public.verification_status not null default 'pending',
  reviewed_by   uuid references public.profiles(id) on delete set null,
  review_note   text,
  submitted_at  timestamptz not null default now(),
  reviewed_at   timestamptz,
  expires_at    timestamptz,
  constraint review_fields_together check (
    (status = 'pending' and reviewed_at is null and reviewed_by is null)
    or (status <> 'pending' and reviewed_at is not null)
  )
);

create index if not exists agency_verifications_agency_idx
  on public.agency_verifications (agency_id, status);
create index if not exists agency_verifications_queue_idx
  on public.agency_verifications (submitted_at) where status = 'pending';

create table if not exists public.consent_records (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  consent_type   public.consent_type not null,
  policy_version text not null,
  granted_at     timestamptz not null default now(),
  revoked_at     timestamptz
);

create index if not exists consent_records_profile_idx
  on public.consent_records (profile_id, consent_type) where revoked_at is null;
-- One live grant per consent type: history is preserved by the revoked_at rows.
create unique index if not exists consent_records_one_live_idx
  on public.consent_records (profile_id, consent_type) where revoked_at is null;

create table if not exists public.audit_logs (
  id           uuid primary key default gen_random_uuid(),
  actor_id     uuid references public.profiles(id) on delete set null,
  action       text not null,
  entity_table text not null,
  entity_id    uuid,
  details      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);

create index if not exists audit_logs_created_idx on public.audit_logs (created_at desc);
create index if not exists audit_logs_entity_idx on public.audit_logs (entity_table, entity_id);
create index if not exists audit_logs_actor_idx on public.audit_logs (actor_id);

-- ── New auth user → profile ────────────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.profiles (id, full_name, is_anonymous, locale, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.is_anonymous, false),
    case when new.raw_user_meta_data ->> 'locale' = 'ar' then 'ar' else 'en' end,
    'client'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create or replace trigger agent_profiles_touch_updated_at
  before update on public.agent_profiles
  for each row execute function public.set_updated_at();

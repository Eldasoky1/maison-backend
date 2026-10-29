-- 0006 — Client preference domain.

set search_path = public, extensions;

create table if not exists public.client_preferences (
  client_id              uuid primary key references public.profiles(id) on delete cascade,
  listing_type           public.listing_type,
  currency_code          char(3) references public.currencies(code),
  budget_min             numeric(14, 2) check (budget_min >= 0),
  budget_max             numeric(14, 2) check (budget_max >= 0),
  min_bedrooms           smallint check (min_bedrooms >= 0),
  min_bathrooms          numeric(4, 1) check (min_bathrooms >= 0),
  min_area_sqm           numeric(10, 2) check (min_area_sqm >= 0),
  max_area_sqm           numeric(10, 2) check (max_area_sqm >= 0),
  personalization_enabled boolean not null default true,
  profile_version        integer not null default 1,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint budget_order check (budget_min is null or budget_max is null or budget_min <= budget_max),
  constraint area_order check (min_area_sqm is null or max_area_sqm is null or min_area_sqm <= max_area_sqm)
);

create table if not exists public.preference_styles (
  client_id uuid not null references public.profiles(id) on delete cascade,
  style_id  uuid not null references public.architectural_styles(id) on delete cascade,
  score     smallint not null check (score between -2 and 2 and score <> 0),
  primary key (client_id, style_id)
);

create index if not exists preference_styles_style_idx on public.preference_styles (style_id);

create table if not exists public.preference_amenities (
  client_id  uuid not null references public.profiles(id) on delete cascade,
  amenity_id uuid not null references public.amenities(id) on delete cascade,
  requirement public.requirement_level not null default 'nice',
  primary key (client_id, amenity_id)
);

create index if not exists preference_amenities_amenity_idx on public.preference_amenities (amenity_id);

create table if not exists public.preference_neighborhoods (
  client_id      uuid not null references public.profiles(id) on delete cascade,
  neighborhood_id uuid not null references public.neighborhoods(id) on delete cascade,
  priority       smallint not null default 1 check (priority between 1 and 3),
  primary key (client_id, neighborhood_id)
);

create index if not exists preference_neighborhoods_hood_idx
  on public.preference_neighborhoods (neighborhood_id);

create table if not exists public.preference_property_types (
  client_id        uuid not null references public.profiles(id) on delete cascade,
  property_type_id uuid not null references public.property_types(id) on delete cascade,
  primary key (client_id, property_type_id)
);

create table if not exists public.preference_updates (
  id                uuid primary key default gen_random_uuid(),
  client_id         uuid not null references public.profiles(id) on delete cascade,
  source_message_id uuid references public.messages(id) on delete set null,
  origin            public.preference_origin not null default 'manual',
  field_path        text not null,
  proposed_value    jsonb not null,
  previous_value    jsonb,
  confidence        numeric(3, 2) not null check (confidence between 0 and 1),
  reason            text,
  status            public.preference_status not null default 'pending',
  created_at        timestamptz not null default now(),
  resolved_at       timestamptz,
  -- Whitelist: the extraction model may only propose these paths.
  constraint preference_updates_field_whitelist check (field_path in (
    'listing_type', 'currency_code', 'budget_min', 'budget_max',
    'min_bedrooms', 'min_bathrooms', 'min_area_sqm', 'max_area_sqm',
    'style', 'amenity', 'neighborhood', 'property_type'
  )),
  constraint resolved_when_settled check (
    (status = 'pending' and resolved_at is null)
    or (status <> 'pending' and resolved_at is not null)
  )
);

create index if not exists preference_updates_client_idx
  on public.preference_updates (client_id, created_at desc);
create index if not exists preference_updates_pending_idx
  on public.preference_updates (client_id) where status = 'pending';

create or replace trigger client_preferences_touch_updated_at
  before update on public.client_preferences
  for each row execute function public.set_updated_at();

-- Bumping profile_version is what invalidates every cached personalization surface.
create or replace function public.bump_profile_version()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_client uuid;
begin
  v_client := coalesce(new.client_id, old.client_id);
  update public.client_preferences
     set profile_version = profile_version + 1
   where client_id = v_client;
  return coalesce(new, old);
end;
$$;

drop trigger if exists preference_styles_version on public.preference_styles;
create trigger preference_styles_version
  after insert or update or delete on public.preference_styles
  for each row execute function public.bump_profile_version();

drop trigger if exists preference_amenities_version on public.preference_amenities;
create trigger preference_amenities_version
  after insert or update or delete on public.preference_amenities
  for each row execute function public.bump_profile_version();

drop trigger if exists preference_neighborhoods_version on public.preference_neighborhoods;
create trigger preference_neighborhoods_version
  after insert or update or delete on public.preference_neighborhoods
  for each row execute function public.bump_profile_version();

drop trigger if exists preference_property_types_version on public.preference_property_types;
create trigger preference_property_types_version
  after insert or update or delete on public.preference_property_types
  for each row execute function public.bump_profile_version();

-- Keep a preferences row for every client so the version trigger always has a target.
create or replace function public.ensure_client_preferences()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.role = 'client' then
    insert into public.client_preferences (client_id) values (new.id)
    on conflict (client_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_ensure_preferences on public.profiles;
create trigger profiles_ensure_preferences
  after insert on public.profiles
  for each row execute function public.ensure_client_preferences();

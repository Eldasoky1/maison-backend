-- 0004 — Property catalog domain.

set search_path = public, extensions;

create table if not exists public.properties (
  id              uuid primary key default gen_random_uuid(),
  agent_id        uuid not null references public.profiles(id) on delete restrict,
  neighborhood_id uuid not null references public.neighborhoods(id) on delete restrict,
  property_type_id uuid not null references public.property_types(id) on delete restrict,
  reference_code  text not null unique,
  listing_type    public.listing_type not null,
  status          public.listing_status not null default 'draft',
  price           numeric(14, 2) not null check (price > 0),
  currency_code   char(3) not null references public.currencies(code),
  bedrooms        smallint not null default 0 check (bedrooms >= 0),
  bathrooms       numeric(4, 1) not null default 0 check (bathrooms >= 0),
  area_sqm        numeric(10, 2) not null check (area_sqm > 0),
  floor_number    smallint,
  year_built      smallint check (year_built between 1000 and 2200),
  address_line    text not null,
  location        geography(point, 4326) not null,
  embedding       vector(1536),
  embedding_stale boolean not null default true,
  published_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- Required by the composite foreign key from viewing_requests. A listing's
  -- agent is a fact of the listing, and the viewing must reference that same pair.
  constraint properties_id_agent_key unique (id, agent_id)
);

create index if not exists properties_agent_idx on public.properties (agent_id);
create index if not exists properties_neighborhood_idx on public.properties (neighborhood_id);
create index if not exists properties_type_idx on public.properties (property_type_id);
create index if not exists properties_public_idx
  on public.properties (status, listing_type, price)
  where status in ('active', 'under_offer');
create index if not exists properties_location_gix on public.properties using gist (location);
create index if not exists properties_published_idx on public.properties (published_at desc nulls last);
create index if not exists properties_reference_trgm_idx
  on public.properties using gin (reference_code gin_trgm_ops);

create table if not exists public.property_translations (
  property_id uuid not null references public.properties(id) on delete cascade,
  locale      text not null check (char_length(locale) = 2),
  title       text not null,
  description text not null default '',
  -- Deliberate exception 3 (documented): search_text is a generated tsvector.
  -- It is fully derived from title + description, so the row stays in 3NF.
  search_text tsvector generated always as (
    to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(description, ''))
  ) stored,
  primary key (property_id, locale)
);

create index if not exists property_translations_search_idx
  on public.property_translations using gin (search_text);

create table if not exists public.property_images (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties(id) on delete cascade,
  media_kind   public.media_kind not null default 'photo',
  storage_path text not null,
  alt_text     text,
  sort_order   smallint not null default 0,
  is_cover     boolean not null default false,
  width        integer,
  height       integer,
  created_at   timestamptz not null default now()
);

create index if not exists property_images_property_idx
  on public.property_images (property_id, sort_order);
create unique index if not exists property_images_one_cover_idx
  on public.property_images (property_id) where is_cover;

create table if not exists public.property_amenities (
  property_id uuid not null references public.properties(id) on delete cascade,
  amenity_id  uuid not null references public.amenities(id) on delete cascade,
  primary key (property_id, amenity_id)
);

create index if not exists property_amenities_amenity_idx on public.property_amenities (amenity_id);

create table if not exists public.property_styles (
  property_id uuid not null references public.properties(id) on delete cascade,
  style_id    uuid not null references public.architectural_styles(id) on delete cascade,
  source      public.style_source not null default 'agent',
  confidence  numeric(3, 2) not null default 1.0 check (confidence between 0 and 1),
  is_primary  boolean not null default false,
  primary key (property_id, style_id)
);

create unique index if not exists property_styles_one_primary_idx
  on public.property_styles (property_id) where is_primary;

create table if not exists public.property_price_history (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  price       numeric(14, 2) not null check (price > 0),
  changed_by  uuid references public.profiles(id) on delete set null,
  changed_at  timestamptz not null default now()
);

create index if not exists property_price_history_property_idx
  on public.property_price_history (property_id, changed_at desc);

create or replace trigger properties_touch_updated_at
  before update on public.properties
  for each row execute function public.set_updated_at();

-- Keep published_at honest and history complete.
create or replace function public.properties_before_update()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if new.status in ('active', 'under_offer') and old.status = 'draft' and new.published_at is null then
    new.published_at = now();
  end if;

  if new.price <> old.price then
    insert into public.property_price_history (property_id, price, changed_by)
    values (new.id, new.price, auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists properties_before_update on public.properties;
create trigger properties_before_update
  before update on public.properties
  for each row execute function public.properties_before_update();

-- Any change that could alter the text or taste of a listing invalidates its vector.
create or replace function public.mark_embedding_stale()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
declare
  v_property uuid;
begin
  v_property := case
    when tg_table_name = 'property_translations' then coalesce(new.property_id, old.property_id)
    when tg_table_name = 'property_amenities' then coalesce(new.property_id, old.property_id)
    when tg_table_name = 'property_styles' then coalesce(new.property_id, old.property_id)
    else null
  end;
  if v_property is not null then
    update public.properties set embedding_stale = true where id = v_property;
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists property_translations_stale on public.property_translations;
create trigger property_translations_stale
  after insert or update or delete on public.property_translations
  for each row execute function public.mark_embedding_stale();

drop trigger if exists property_amenities_stale on public.property_amenities;
create trigger property_amenities_stale
  after insert or update or delete on public.property_amenities
  for each row execute function public.mark_embedding_stale();

drop trigger if exists property_styles_stale on public.property_styles;
create trigger property_styles_stale
  after insert or update or delete on public.property_styles
  for each row execute function public.mark_embedding_stale();

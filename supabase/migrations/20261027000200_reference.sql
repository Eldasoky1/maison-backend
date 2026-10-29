-- 0002 — Reference domain: currencies, countries, cities, neighborhoods,
-- architectural styles, amenity taxonomy, property types, hero variants.

set search_path = public, extensions;

create table if not exists public.currencies (
  code         char(3) primary key,
  name         text not null,
  symbol       text not null,
  minor_units  smallint not null default 2 check (minor_units between 0 and 4),
  created_at   timestamptz not null default now()
);

create table if not exists public.countries (
  code                  char(2) primary key,
  name                  text not null,
  default_currency_code char(3) not null references public.currencies(code),
  phone_prefix          text not null,
  created_at            timestamptz not null default now()
);

create table if not exists public.cities (
  id           uuid primary key default gen_random_uuid(),
  country_code char(2) not null references public.countries(code),
  name         text not null,
  slug         text not null unique,
  center       geography(point, 4326) not null,
  timezone     text not null,
  created_at   timestamptz not null default now()
);

create index if not exists cities_center_gix on public.cities using gist (center);

create table if not exists public.neighborhoods (
  id          uuid primary key default gen_random_uuid(),
  city_id     uuid not null references public.cities(id) on delete cascade,
  name        text not null,
  slug        text not null unique,
  center      geography(point, 4326) not null,
  boundary    geography(polygon, 4326),
  description text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create index if not exists neighborhoods_city_idx on public.neighborhoods (city_id);
create index if not exists neighborhoods_center_gix on public.neighborhoods using gist (center);
create index if not exists neighborhoods_boundary_gix on public.neighborhoods using gist (boundary);

create table if not exists public.architectural_styles (
  id                  uuid primary key default gen_random_uuid(),
  code                text not null unique,
  name                text not null,
  description         text,
  reference_image_path text,
  display_order       smallint not null default 0,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now()
);

create table if not exists public.amenity_categories (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  name          text not null,
  display_order smallint not null default 0,
  created_at    timestamptz not null default now()
);

create table if not exists public.amenities (
  id          uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.amenity_categories(id) on delete cascade,
  code        text not null unique,
  name        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create index if not exists amenities_category_idx on public.amenities (category_id);

create table if not exists public.property_types (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  name          text not null,
  display_order smallint not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

create table if not exists public.hero_variants (
  id           uuid primary key default gen_random_uuid(),
  style_id     uuid references public.architectural_styles(id) on delete set null,
  locale       text not null default 'en' check (char_length(locale) = 2),
  headline     text not null,
  subheadline  text,
  cta_label    text not null default 'Explore the collection',
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

create index if not exists hero_variants_style_idx on public.hero_variants (style_id, locale) where is_active;

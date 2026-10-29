-- 0008 — Database logic: identity helpers, public projections, ranking engine.

set search_path = public, extensions;

-- ── Identity helpers ────────────────────────────────────────────────────────
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

create or replace function public.is_agent()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('agent', 'admin')
  );
$$;

-- An agency is verified when an approved, unexpired verification exists.
-- SECURITY DEFINER so the public listing policy can call it without exposing
-- the verification table itself. It returns a boolean and nothing else.
create or replace function public.is_agency_verified(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.agency_verifications v
    where v.agency_id = p_agency_id
      and v.status = 'approved'
      and (v.expires_at is null or v.expires_at > now())
  );
$$;

revoke all on function public.is_admin() from public;
revoke all on function public.is_agent() from public;
revoke all on function public.is_agency_verified(uuid) from public;
grant execute on function public.is_admin() to anon, authenticated, service_role;
grant execute on function public.is_agent() to anon, authenticated, service_role;
grant execute on function public.is_agency_verified(uuid) to anon, authenticated, service_role;

-- ── Public projections ──────────────────────────────────────────────────────
-- These views are owned by the migration role and therefore bypass RLS. That is
-- deliberate: each one applies its own explicit visibility predicate and only
-- projects columns that are safe to publish. They are the only public read path
-- for listing cards and agent cards.
create or replace view public.listing_cards as
select
  p.id,
  p.reference_code,
  p.listing_type,
  p.status,
  p.price,
  p.currency_code,
  cur.symbol as currency_symbol,
  p.bedrooms,
  p.bathrooms,
  p.area_sqm,
  p.floor_number,
  p.year_built,
  p.address_line,
  p.neighborhood_id,
  n.name as neighborhood_name,
  n.slug as neighborhood_slug,
  c.id as city_id,
  c.name as city_name,
  c.slug as city_slug,
  p.property_type_id,
  t.name as property_type_name,
  p.agent_id,
  pr.full_name as agent_name,
  ag.id as agency_id,
  ag.name as agency_name,
  lower(regexp_replace(coalesce(ag.name, ''), '[^a-zA-Z0-9]+', '-', 'g')) as agency_slug,
  p.published_at,
  p.created_at,
  coalesce(pt.title, p.reference_code) as title,
  coalesce(pt.description, '') as description,
  img.storage_path as cover_path,
  img.alt_text as cover_alt,
  st.name as primary_style_name,
  st.id as primary_style_id,
  p.location
from public.properties p
join public.profiles pr on pr.id = p.agent_id
left join public.agencies ag on ag.id = pr.agency_id
left join public.agency_verifications av
  on av.agency_id = pr.agency_id and av.status = 'approved'
     and (av.expires_at is null or av.expires_at > now())
join public.neighborhoods n on n.id = p.neighborhood_id
join public.cities c on c.id = n.city_id
join public.property_types t on t.id = p.property_type_id
join public.currencies cur on cur.code = p.currency_code
left join public.property_translations pt
  on pt.property_id = p.id and pt.locale = 'en'
left join lateral (
  select pi.storage_path, pi.alt_text
  from public.property_images pi
  where pi.property_id = p.id and pi.is_cover
  limit 1
) img on true
left join lateral (
  select s.id, s.name
  from public.property_styles ps
  join public.architectural_styles s on s.id = ps.style_id
  where ps.property_id = p.id and ps.is_primary
  limit 1
) st on true
where p.status in ('active', 'under_offer')
  and av.id is not null;

comment on view public.listing_cards is
  'Public listing projection. Filters to live listings of verified agencies; safe for anon.';

create or replace view public.agent_directory as
select
  pr.id,
  pr.full_name,
  pr.avatar_path,
  pr.agency_id,
  ag.name as agency_name,
  ag.city_id,
  ci.name as city_name,
  ap.display_title,
  ap.bio,
  ap.years_experience,
  ap.public_phone,
  ap.is_accepting_viewings,
  (select count(*) from public.properties p
    where p.agent_id = pr.id and p.status in ('active', 'under_offer')) as live_listings
from public.profiles pr
join public.agent_profiles ap on ap.profile_id = pr.id
left join public.agencies ag on ag.id = pr.agency_id
left join public.cities ci on ci.id = ag.city_id
where pr.role in ('agent', 'admin');

comment on view public.agent_directory is
  'Public agent projection. Exposes only the public business columns.';

grant select on public.listing_cards to anon, authenticated;
grant select on public.agent_directory to anon, authenticated;

-- ── Ranking engine ──────────────────────────────────────────────────────────
-- Hard filters, then a transparent 0.35/0.25/0.20/0.20 score. Reasons are
-- composed in SQL so the language model never invents an explanation.
create or replace function public.match_properties(
  p_client_id uuid default auth.uid(),
  p_limit integer default 24,
  p_offset integer default 0,
  p_sort text default 'relevance'
)
returns table (
  id uuid,
  reference_code text,
  listing_type public.listing_type,
  status public.listing_status,
  price numeric,
  currency_code char(3),
  currency_symbol text,
  bedrooms smallint,
  bathrooms numeric,
  area_sqm numeric,
  neighborhood_id uuid,
  neighborhood_name text,
  neighborhood_slug text,
  city_name text,
  property_type_name text,
  title text,
  description text,
  cover_path text,
  cover_alt text,
  agent_id uuid,
  agent_name text,
  primary_style_name text,
  published_at timestamptz,
  match_score numeric,
  semantic_score numeric,
  style_score numeric,
  amenity_score numeric,
  neighborhood_score numeric,
  reasons text[]
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_pref public.client_preferences%rowtype;
  v_active boolean := false;
  v_taste vector(1536);
  v_has_types boolean := false;
  v_has_hoods boolean := false;
  v_has_nice boolean := false;
begin
  if p_client_id is null then
    raise exception 'client id is required' using errcode = '22004';
  end if;
  -- A caller may only ask for their own matches. Service role (no JWT) may pass any id.
  if v_uid is not null and v_uid <> p_client_id and not public.is_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  select * into v_pref from public.client_preferences where client_id = p_client_id;

  v_active := coalesce(v_pref.personalization_enabled, false)
    and exists (
      select 1 from public.consent_records cr
      where cr.profile_id = p_client_id
        and cr.consent_type = 'profiling'
        and cr.revoked_at is null
    );

  if v_active then
    select avg(p.embedding) into v_taste
    from public.property_styles ps
    join public.properties p on p.id = ps.property_id
    join public.preference_styles pref
      on pref.style_id = ps.style_id
     and pref.client_id = p_client_id
     and pref.score > 0
    where ps.is_primary and p.embedding is not null;

    select exists (select 1 from public.preference_property_types where client_id = p_client_id)
      into v_has_types;
    select exists (select 1 from public.preference_neighborhoods where client_id = p_client_id)
      into v_has_hoods;
    select exists (select 1 from public.preference_amenities where client_id = p_client_id and requirement = 'nice')
      into v_has_nice;
  end if;

  return query
  with candidates as (
    select
      p.id, p.reference_code, p.listing_type, p.status, p.price, p.currency_code,
      cur.symbol as currency_symbol, p.bedrooms, p.bathrooms, p.area_sqm,
      n.id as hood_id, n.name as hood_name, n.slug as hood_slug, c.name as city_name,
      pt.name as type_name,
      coalesce(tr.title, p.reference_code) as title,
      coalesce(tr.description, '') as description,
      img.storage_path as cover_path, img.alt_text as cover_alt,
      p.agent_id, pr.full_name as agent_name,
      st.name as style_name, st.id as style_id,
      p.published_at, p.embedding, p.location, p.neighborhood_id,
      pref_style.score as style_pref
    from public.properties p
    join public.profiles pr on pr.id = p.agent_id
    join public.agency_verifications av
      on av.agency_id = pr.agency_id and av.status = 'approved'
         and (av.expires_at is null or av.expires_at > now())
    join public.neighborhoods n on n.id = p.neighborhood_id
    join public.cities c on c.id = n.city_id
    join public.property_types pt on pt.id = p.property_type_id
    join public.currencies cur on cur.code = p.currency_code
    left join public.property_translations tr
      on tr.property_id = p.id and tr.locale = 'en'
    left join lateral (
      select pi.storage_path, pi.alt_text from public.property_images pi
      where pi.property_id = p.id and pi.is_cover limit 1
    ) img on true
    left join lateral (
      select s.id, s.name, psty.score
      from public.property_styles psty
      join public.architectural_styles s on s.id = psty.style_id
      where psty.property_id = p.id and psty.is_primary
      limit 1
    ) st on true
    left join public.preference_styles pref_style
      on pref_style.client_id = p_client_id and pref_style.style_id = st.id
    where p.status in ('active', 'under_offer')
      and (
        not v_active
        or (
          (v_pref.listing_type is null or p.listing_type = v_pref.listing_type)
          and (v_pref.currency_code is null or p.currency_code = v_pref.currency_code)
          and (v_pref.budget_min is null or p.price >= v_pref.budget_min * 0.90)
          and (v_pref.budget_max is null or p.price <= v_pref.budget_max * 1.10)
          and (v_pref.min_bedrooms is null or p.bedrooms >= v_pref.min_bedrooms)
          and (v_pref.min_bathrooms is null or p.bathrooms >= v_pref.min_bathrooms)
          and (v_pref.min_area_sqm is null or p.area_sqm >= v_pref.min_area_sqm)
          and (v_pref.max_area_sqm is null or p.area_sqm <= v_pref.max_area_sqm)
          and (
            not v_has_types or p.property_type_id in (
              select property_type_id from public.preference_property_types where client_id = p_client_id
            )
          )
          and not exists (
            select 1 from public.preference_amenities pa
            where pa.client_id = p_client_id and pa.requirement = 'must'
              and not exists (
                select 1 from public.property_amenities pam
                where pam.property_id = p.id and pam.amenity_id = pa.amenity_id
              )
          )
          and (
            not v_has_hoods or exists (
              select 1
              from public.preference_neighborhoods pn
              join public.neighborhoods pn_n on pn_n.id = pn.neighborhood_id
              where pn.client_id = p_client_id
                and (p.neighborhood_id = pn.neighborhood_id
                     or st_dwithin(p.location, pn_n.center, 2000))
            )
          )
        )
      )
  ),
  scored as (
    select
      c.*,
      case
        when not v_active then 0.5::numeric
        when v_taste is null or c.embedding is null then 0.5::numeric
        else greatest(0, least(1, 1 - (c.embedding <=> v_taste)))::numeric
      end as s_semantic,
      case
        when not v_active or c.style_id is null then 0.5::numeric
        when c.style_pref is null then 0.5::numeric
        when c.style_pref < 0 then 0.15::numeric
        else least(1.0, 0.70 + (c.style_pref * 0.15))::numeric
      end as s_style,
      case
        when not v_active or not v_has_nice then 0.5::numeric
        else (
          0.5 + 0.5 * (
            select count(*)::numeric
            from public.preference_amenities pa
            join public.property_amenities pam
              on pam.amenity_id = pa.amenity_id and pam.property_id = c.id
            where pa.client_id = p_client_id and pa.requirement = 'nice'
          ) / greatest(1, (
            select count(*) from public.preference_amenities
            where client_id = p_client_id and requirement = 'nice'
          ))
        )
      end as s_amenity,
      case
        when not v_active or not v_has_hoods then 0.5::numeric
        else coalesce(
          (select case pn.priority when 3 then 1.0 when 2 then 0.85 else 0.70 end
           from public.preference_neighborhoods pn
           where pn.client_id = p_client_id and pn.neighborhood_id = c.neighborhood_id),
          case when exists (
            select 1 from public.preference_neighborhoods pn
            join public.neighborhoods nn on nn.id = pn.neighborhood_id
            where pn.client_id = p_client_id
              and st_dwithin(c.location, nn.center, 2000)
          ) then 0.60 else 0.50 end
        )::numeric
      end as s_hood,
      array_remove(array[
        case when v_active and c.style_pref is not null and c.style_pref > 0
             then 'Matches your taste for ' || c.style_name end,
        case when v_active and c.style_pref is not null and c.style_pref < 0
             then 'A style you usually pass on' end,
        case when v_active and c.style_pref is null and c.style_name is not null
             then c.style_name || ' architecture' end,
        case when v_active and v_has_nice and (
               select count(*) from public.preference_amenities pa
               join public.property_amenities pam
                 on pam.amenity_id = pa.amenity_id and pam.property_id = c.id
               where pa.client_id = p_client_id and pa.requirement = 'nice'
             ) > 0
             then (
               select count(*)::text from public.preference_amenities pa
               join public.property_amenities pam
                 on pam.amenity_id = pa.amenity_id and pam.property_id = c.id
               where pa.client_id = p_client_id and pa.requirement = 'nice'
             ) || ' of your preferred amenities' end,
        case when v_active and v_has_hoods and exists (
               select 1 from public.preference_neighborhoods pn
               where pn.client_id = p_client_id and pn.neighborhood_id = c.neighborhood_id
             )
             then 'In ' || c.hood_name || ', one of your chosen neighborhoods' end,
        case when v_active and c.hood_name is not null then 'In ' || c.hood_name end,
        case when v_active and v_pref.budget_max is not null and c.price <= v_pref.budget_max
             then 'Within your budget' end,
        c.bedrooms::text || ' bedrooms · ' || round(c.area_sqm)::text || ' m²'
      ], null) as reason_list
    from candidates c
  )
  select
    s.id, s.reference_code, s.listing_type, s.status, s.price, s.currency_code,
    s.currency_symbol, s.bedrooms, s.bathrooms, s.area_sqm,
    s.hood_id, s.hood_name, s.hood_slug, s.city_name, s.type_name,
    s.title, s.description, s.cover_path, s.cover_alt,
    s.agent_id, s.agent_name, s.style_name, s.published_at,
    round(0.35 * s.s_semantic + 0.25 * s.s_style + 0.20 * s.s_amenity + 0.20 * s.s_hood, 4) as match_score,
    round(s.s_semantic, 4), round(s.s_style, 4), round(s.s_amenity, 4), round(s.s_hood, 4),
    s.reason_list
  from scored s
  order by
    case when p_sort = 'price_asc' then s.price end asc nulls last,
    case when p_sort = 'price_desc' then s.price end desc nulls last,
    case when p_sort = 'newest' then s.published_at end desc nulls last,
    case when p_sort = 'relevance' and v_active then
      (0.35 * s.s_semantic + 0.25 * s.s_style + 0.20 * s.s_amenity + 0.20 * s.s_hood)
    end desc nulls last,
    s.published_at desc nulls last
  limit greatest(1, least(coalesce(p_limit, 24), 60))
  offset greatest(0, coalesce(p_offset, 0));
end;
$$;

revoke all on function public.match_properties(uuid, integer, integer, text) from public;
grant execute on function public.match_properties(uuid, integer, integer, text)
  to anon, authenticated, service_role;

-- ── Price-drop notifications for clients who saved the listing ─────────────
create or replace function public.notify_price_drop()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_previous numeric;
begin
  select price into v_previous
  from public.property_price_history
  where property_id = new.property_id and id <> new.id
  order by changed_at desc
  limit 1;

  if v_previous is not null and new.price < v_previous then
    insert into public.notifications (recipient_id, type, property_id, body)
    select distinct ci.client_id, 'price_drop', new.property_id,
           'The price of a home you saved has changed'
    from public.collection_items ci
    where ci.property_id = new.property_id;
  end if;
  return new;
end;
$$;

drop trigger if exists property_price_history_notify on public.property_price_history;
create trigger property_price_history_notify
  after insert on public.property_price_history
  for each row execute function public.notify_price_drop();

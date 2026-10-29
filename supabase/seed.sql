-- seed.sql — reference data, demo personas and 30 synthetic listings.
-- Run with `supabase db reset`. Demo password for every seeded account:
--   MaisonDemo!2026
-- Images live in /public/seed and are also uploaded by `npm run seed:images`.

set search_path = public, extensions;
set client_min_messages = warning;

-- ── Reference ───────────────────────────────────────────────────────────────
insert into public.currencies (code, name, symbol, minor_units) values
  ('EUR', 'Euro', '€', 2),
  ('AED', 'UAE Dirham', 'AED', 2),
  ('USD', 'US Dollar', '$', 2)
on conflict (code) do nothing;

insert into public.countries (code, name, default_currency_code, phone_prefix) values
  ('FR', 'France', 'EUR', '+33'),
  ('AE', 'United Arab Emirates', 'AED', '+971')
on conflict (code) do nothing;

insert into public.cities (id, country_code, name, slug, center, timezone) values
  ('11111111-1111-4111-8111-111111111111', 'FR', 'Paris', 'paris',
    st_setsrid(st_makepoint(2.3522, 48.8566), 4326)::geography, 'Europe/Paris'),
  ('11111111-1111-4111-8111-111111111112', 'AE', 'Dubai', 'dubai',
    st_setsrid(st_makepoint(55.2708, 25.2048), 4326)::geography, 'Asia/Dubai'),
  ('11111111-1111-4111-8111-111111111113', 'AE', 'Abu Dhabi', 'abu-dhabi',
    st_setsrid(st_makepoint(54.3773, 24.4539), 4326)::geography, 'Asia/Dubai')
on conflict (id) do nothing;

insert into public.neighborhoods (id, city_id, name, slug, center, description) values
  ('22222222-2222-4222-8222-222222222201', '11111111-1111-4111-8111-111111111111', 'Le Marais', 'le-marais',
    st_setsrid(st_makepoint(2.3622, 48.8590), 4326)::geography,
    'Seventeenth-century hôtels particuliers, quiet courtyards and a dense gallery culture between the Seine and the boulevard.'),
  ('22222222-2222-4222-8222-222222222202', '11111111-1111-4111-8111-111111111111', 'Saint-Germain-des-Prés', 'saint-germain',
    st_setsrid(st_makepoint(2.3338, 48.8540), 4326)::geography,
    'The literary left bank: bookshops, café terraces and grand bourgeois apartments behind stone facades.'),
  ('22222222-2222-4222-8222-222222222203', '11111111-1111-4111-8111-111111111111', '7e Arrondissement', 'paris-7e',
    st_setsrid(st_makepoint(2.3120, 48.8560), 4326)::geography,
    'Haussmannian formality, embassy gardens and the Eiffel Tower at the end of the street.'),
  ('22222222-2222-4222-8222-222222222204', '11111111-1111-4111-8111-111111111111', 'Montmartre', 'montmartre',
    st_setsrid(st_makepoint(2.3431, 48.8867), 4326)::geography,
    'Village-scale streets, artist studios and views across the northern roofs.'),
  ('22222222-2222-4222-8222-222222222205', '11111111-1111-4111-8111-111111111112', 'Palm Jumeirah', 'palm-jumeirah',
    st_setsrid(st_makepoint(55.1385, 25.1124), 4326)::geography,
    'Beachfront villas on the palm, oriented to the skyline and the open Gulf.'),
  ('22222222-2222-4222-8222-222222222206', '11111111-1111-4111-8111-111111111112', 'Downtown Dubai', 'downtown-dubai',
    st_setsrid(st_makepoint(55.2744, 25.1972), 4326)::geography,
    'Vertical living around the Burj Khalifa, with opera, fountain and retail at street level.'),
  ('22222222-2222-4222-8222-222222222207', '11111111-1111-4111-8111-111111111112', 'Jumeirah Bay', 'jumeirah-bay',
    st_setsrid(st_makepoint(55.2410, 25.2050), 4326)::geography,
    'An island of low-rise villas and a single sculptural tower, minutes from the coast road.'),
  ('22222222-2222-4222-8222-222222222208', '11111111-1111-4111-8111-111111111112', 'Emirates Hills', 'emirates-hills',
    st_setsrid(st_makepoint(55.1730, 25.0730), 4326)::geography,
    'Gated estate villas set against the Montgomerie golf course.'),
  ('22222222-2222-4222-8222-222222222209', '11111111-1111-4111-8111-111111111113', 'Saadiyat Island', 'saadiyat',
    st_setsrid(st_makepoint(54.4380, 24.5390), 4326)::geography,
    'Museum district, protected beach and a low-density masterplan of cultural institutions.'),
  ('22222222-2222-4222-8222-222222222210', '11111111-1111-4111-8111-111111111113', 'Al Reem Island', 'al-reem',
    st_setsrid(st_makepoint(54.4040, 24.4980), 4326)::geography,
    'Waterfront towers with skyline views and a walkable promenade.'),
  ('22222222-2222-4222-8222-222222222211', '11111111-1111-4111-8111-111111111113', 'Khalifa City', 'khalifa-city',
    st_setsrid(st_makepoint(54.5730, 24.4230), 4326)::geography,
    'Villa neighbourhoods, international schools and generous plots.'),
  ('22222222-2222-4222-8222-222222222212', '11111111-1111-4111-8111-111111111113', 'Yas Island', 'yas-island',
    st_setsrid(st_makepoint(54.6000, 24.4900), 4326)::geography,
    'Marina residences, motorsport and a resort-scale waterfront.')
on conflict (id) do nothing;

insert into public.architectural_styles (id, code, name, description, reference_image_path, display_order) values
  ('33333333-3333-4333-8333-333333333301', 'haussmannian', 'Haussmannian',
    'Limestone facades, tall French windows, parquet de Versailles and a disciplined street rhythm.', 'seed/style-haussmannian.svg', 1),
  ('33333333-3333-4333-8333-333333333302', 'contemporary', 'Contemporary',
    'Quiet volumes, full-height glazing and a palette of pale stone, oak and brushed metal.', 'seed/style-contemporary.svg', 2),
  ('33333333-3333-4333-8333-333333333303', 'modernist', 'Modernist',
    'Post-war clarity: horizontal ribbon windows, pilotis and open-plan living.', 'seed/style-modernist.svg', 3),
  ('33333333-3333-4333-8333-333333333304', 'art-deco', 'Art Deco',
    'Stepped geometry, lacquer, fluted timber and a confident use of brass.', 'seed/style-art-deco.svg', 4),
  ('33333333-3333-4333-8333-333333333305', 'mediterranean', 'Mediterranean',
    'Lime plaster, deep loggias, terracotta and rooms that open to the garden.', 'seed/style-mediterranean.svg', 5),
  ('33333333-3333-4333-8333-333333333306', 'minimalist', 'Minimalist',
    'Few materials, precise joints, concealed storage and an absence of ornament.', 'seed/style-minimalist.svg', 6),
  ('33333333-3333-4333-8333-333333333307', 'brutalist', 'Brutalist',
    'Board-formed concrete, sculptural stairs and a monumental sense of shelter.', 'seed/style-brutalist.svg', 7),
  ('33333333-3333-4333-8333-333333333308', 'traditional', 'Traditional',
    'Regional craft, pitched roofs, shutters and materials that age well.', 'seed/style-traditional.svg', 8)
on conflict (id) do nothing;

insert into public.amenity_categories (id, code, name, display_order) values
  ('44444444-4444-4444-8444-444444444401', 'wellness', 'Wellness', 1),
  ('44444444-4444-4444-8444-444444444402', 'outdoor', 'Outdoor', 2),
  ('44444444-4444-4444-8444-444444444403', 'smart', 'Smart home', 3),
  ('44444444-4444-4444-8444-444444444404', 'security', 'Security', 4),
  ('44444444-4444-4444-8444-444444444405', 'parking', 'Parking', 5),
  ('44444444-4444-4444-8444-444444444406', 'views', 'Views', 6),
  ('44444444-4444-4444-8444-444444444407', 'services', 'Services', 7)
on conflict (id) do nothing;

insert into public.amenities (category_id, code, name) values
  ('44444444-4444-4444-8444-444444444401', 'pool', 'Swimming pool'),
  ('44444444-4444-4444-8444-444444444401', 'spa', 'Spa'),
  ('44444444-4444-4444-8444-444444444401', 'gym', 'Private gym'),
  ('44444444-4444-4444-8444-444444444401', 'hammam', 'Hammam'),
  ('44444444-4444-4444-8444-444444444402', 'terrace', 'Terrace'),
  ('44444444-4444-4444-8444-444444444402', 'garden', 'Private garden'),
  ('44444444-4444-4444-8444-444444444402', 'balcony', 'Balcony'),
  ('44444444-4444-4444-8444-444444444402', 'roof-terrace', 'Roof terrace'),
  ('44444444-4444-4444-8444-444444444403', 'home-automation', 'Home automation'),
  ('44444444-4444-4444-8444-444444444403', 'climate-control', 'Climate control'),
  ('44444444-4444-4444-8444-444444444403', 'sound-system', 'Integrated sound'),
  ('44444444-4444-4444-8444-444444444403', 'ev-charging', 'EV charging'),
  ('44444444-4444-4444-8444-444444444404', 'concierge', 'Concierge'),
  ('44444444-4444-4444-8444-444444444404', 'doorman', 'Doorman'),
  ('44444444-4444-4444-8444-444444444404', 'cctv', 'CCTV'),
  ('44444444-4444-4444-8444-444444444404', 'gated', 'Gated estate'),
  ('44444444-4444-4444-8444-444444444405', 'garage', 'Garage'),
  ('44444444-4444-4444-8444-444444444405', 'parking', 'Secure parking'),
  ('44444444-4444-4444-8444-444444444405', 'valet', 'Valet'),
  ('44444444-4444-4444-8444-444444444405', 'car-lift', 'Car lift'),
  ('44444444-4444-4444-8444-444444444406', 'sea-view', 'Sea view'),
  ('44444444-4444-4444-8444-444444444406', 'skyline-view', 'Skyline view'),
  ('44444444-4444-4444-8444-444444444406', 'garden-view', 'Garden view'),
  ('44444444-4444-4444-8444-444444444406', 'city-view', 'City view'),
  ('44444444-4444-4444-8444-444444444407', 'elevator', 'Elevator'),
  ('44444444-4444-4444-8444-444444444407', 'fireplace', 'Fireplace'),
  ('44444444-4444-4444-8444-444444444407', 'wine-cellar', 'Wine cellar'),
  ('44444444-4444-4444-8444-444444444407', 'staff-quarters', 'Staff quarters')
on conflict (code) do nothing;

insert into public.property_types (id, code, name, display_order) values
  ('55555555-5555-4555-8555-555555555501', 'apartment', 'Apartment', 1),
  ('55555555-5555-4555-8555-555555555502', 'penthouse', 'Penthouse', 2),
  ('55555555-5555-4555-8555-555555555503', 'villa', 'Villa', 3),
  ('55555555-5555-4555-8555-555555555504', 'townhouse', 'Townhouse', 4),
  ('55555555-5555-4555-8555-555555555505', 'loft', 'Loft', 5),
  ('55555555-5555-4555-8555-555555555506', 'mansion', 'Mansion', 6)
on conflict (id) do nothing;

insert into public.hero_variants (style_id, locale, headline, subheadline, cta_label) values
  (null, 'en', 'A quieter way to find a remarkable home.',
    'An advisor that learns what you love, then edits the collection around it.', 'Begin with your taste'),
  ('33333333-3333-4333-8333-333333333301', 'en', 'Stone, light and a certain proportion.',
    'Haussmannian apartments selected for the details that rarely photograph well.', 'See Haussmannian homes'),
  ('33333333-3333-4333-8333-333333333302', 'en', 'Room to breathe, and nothing to add.',
    'Contemporary houses where the plan, the glass and the garden do the work.', 'See contemporary homes'),
  ('33333333-3333-4333-8333-333333333303', 'en', 'The clarity of the post-war plan.',
    'Modernist residences with ribbon windows, open living and generous light.', 'See modernist homes'),
  ('33333333-3333-4333-8333-333333333304', 'en', 'Geometry with a little glamour.',
    'Art Deco apartments in the buildings that still know how to make an entrance.', 'See Art Deco homes'),
  ('33333333-3333-4333-8333-333333333305', 'en', 'Rooms that open to the garden.',
    'Mediterranean houses of plaster, shade and long, slow afternoons.', 'See Mediterranean homes'),
  ('33333333-3333-4333-8333-333333333306', 'en', 'Less, but precisely so.',
    'Minimalist homes where every joint has been considered twice.', 'See minimalist homes'),
  ('33333333-3333-4333-8333-333333333307', 'en', 'Shelter with a sculptural weight.',
    'Brutalist residences for people who like their materials honest.', 'See brutalist homes'),
  ('33333333-3333-4333-8333-333333333308', 'en', 'Built to be lived in for decades.',
    'Traditional houses with regional craft and materials that improve with time.', 'See traditional homes')
on conflict do nothing;

-- ── Demo personas ───────────────────────────────────────────────────────────
do $$
declare
  v_user record;
  v_instance uuid := '00000000-0000-0000-0000-000000000000';
begin
  for v_user in
    select * from (values
      ('a0000000-0000-4000-8000-000000000001'::uuid, 'camille@maison.test', 'Camille Laurent', 'agent', 'en'),
      ('a0000000-0000-4000-8000-000000000002'::uuid, 'omar@maison.test', 'Omar Haddad', 'agent', 'en'),
      ('b0000000-0000-4000-8000-000000000001'::uuid, 'elise@maison.test', 'Élise Moreau', 'client', 'en'),
      ('b0000000-0000-4000-8000-000000000002'::uuid, 'james@maison.test', 'James Whitfield', 'client', 'en'),
      ('b0000000-0000-4000-8000-000000000003'::uuid, 'layla@maison.test', 'Layla Al Mansoori', 'client', 'ar'),
      ('c0000000-0000-4000-8000-000000000001'::uuid, 'admin@maison.test', 'Maison Admin', 'admin', 'en')
    ) as t(id, email, full_name, role, locale)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
    ) values (
      v_instance, v_user.id, 'authenticated', 'authenticated', v_user.email,
      extensions.crypt('MaisonDemo!2026', extensions.gen_salt('bf')),
      now(),
      jsonb_build_object('provider', 'email', 'providers', array['email']),
      jsonb_build_object('full_name', v_user.full_name, 'locale', v_user.locale),
      now(), now(), false
    )
    on conflict (id) do nothing;

    insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      gen_random_uuid(), v_user.id::text, v_user.id,
      jsonb_build_object('sub', v_user.id::text, 'email', v_user.email, 'email_verified', true),
      'email', now(), now(), now()
    )
    on conflict do nothing;

    update public.profiles
       set role = v_user.role::public.user_role,
           full_name = v_user.full_name,
           locale = v_user.locale,
           phone = case when v_user.role = 'agent' then '+33 1 84 80 12 40' else null end
     where id = v_user.id;
  end loop;
end $$;

insert into public.agencies (id, name, license_number, city_id, contact_email, phone) values
  ('66666666-6666-4666-8666-666666666601', 'Maison Privé', 'CPI-7501-2026-0042',
   '11111111-1111-4111-8111-111111111111', 'hello@maisonprive.test', '+33 1 84 80 12 40')
on conflict (id) do nothing;

update public.profiles set agency_id = '66666666-6666-4666-8666-666666666601'
where id in ('a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002');

insert into public.agent_profiles (profile_id, display_title, bio, professional_license_no, years_experience, public_phone, is_accepting_viewings) values
  ('a0000000-0000-4000-8000-000000000001', 'Founding partner · Rive Gauche',
   'Camille works almost exclusively on the left bank, with a particular eye for apartments that have kept their original plan. She represents around twenty families a year and answers her own phone.',
   'CPI-7501-118204', 14, '+33 6 12 44 09 18', true),
  ('a0000000-0000-4000-8000-000000000002', 'Director · Gulf',
   'Omar advises on waterfront and estate villas across Dubai and Abu Dhabi. Before Maison he spent nine years in development, which is why he can tell you what a building will feel like in August.',
   'RERA-44821', 11, '+971 50 224 8890', true)
on conflict (profile_id) do nothing;

insert into public.agency_verifications
  (agency_id, submitted_by, document_path, status, reviewed_by, review_note, submitted_at, reviewed_at, expires_at)
values
  ('66666666-6666-4666-8666-666666666601', 'a0000000-0000-4000-8000-000000000001',
   'seed/maison-prive-license.pdf', 'approved', 'c0000000-0000-4000-8000-000000000001',
   'Carte professionnelle verified against the CCI registry.', now() - interval '40 days',
   now() - interval '39 days', now() + interval '325 days')
on conflict do nothing;

-- ── Listings ────────────────────────────────────────────────────────────────
delete from public.properties where reference_code like 'MR-%';

create temp table seed_listings (
  idx int primary key, reference text unique, agent_slot int, hood_slug text, type_code text,
  listing_type public.listing_type, status public.listing_status, price numeric, currency char(3),
  bedrooms smallint, bathrooms numeric, area numeric, floor smallint, year smallint,
  address text, lat double precision, lng double precision, title text, description text, style_code text
) on commit drop;

insert into seed_listings values
(1, 'MR-101', 1, 'le-marais', 'apartment', 'sale', 'active', 2650000, 'EUR', 4, 3.5, 218, 3, 1868,
 '12 rue de Sévigné, 75004', 48.8572, 2.3635,
 'A four-bedroom hôtel particulier apartment with its original enfilade',
 'Behind a courtyard gate, a first-floor apartment of 218 m² with 3.4 m ceilings, parquet de Versailles and six windows onto the garden. The reception rooms retain their original boiseries; the kitchen was rebuilt in oak and limestone in 2023. A cellar and a service entrance complete the property.', 'haussmannian'),
(2, 'MR-102', 1, 'le-marais', 'loft', 'sale', 'active', 1980000, 'EUR', 2, 2, 156, 4, 1932,
 '8 rue Charlot, 75003', 48.8625, 2.3628,
 'A painter''s loft under a glass roof, off rue Charlot',
 'A former atelier converted into a single open volume with a mezzanine, black steel windows and a 42 m² terrace. The north light is exceptional and entirely protected by the co-ownership. Two bedrooms, a studio and a separate entrance on the courtyard.', 'contemporary'),
(3, 'MR-103', 1, 'saint-germain', 'apartment', 'sale', 'active', 3420000, 'EUR', 3, 2.5, 186, 2, 1880,
 '31 rue de l''Université, 75007', 48.8578, 2.3320,
 'A literary address: three bedrooms over the bookshops',
 'Second floor, 186 m², with a double reception facing south and a library that runs the length of the apartment. Original herringbone parquet, marble fireplaces, and a kitchen by a Burgundian cabinetmaker. Cellar included; parking available in the building next door.', 'haussmannian'),
(4, 'MR-104', 1, 'paris-7e', 'apartment', 'sale', 'active', 4750000, 'EUR', 4, 4, 244, 5, 1901,
 '4 avenue de La Bourdonnais, 75007', 48.8562, 2.2980,
 'A full-floor apartment with the Tower in every window',
 'A rare full-floor apartment of 244 m², with a wraparound balcony and an uninterrupted view of the Eiffel Tower. Four bedrooms, a formal dining room, and a service kitchen. The building has a live-in concierge and a recently restored limestone facade.', 'haussmannian'),
(5, 'MR-105', 1, 'paris-7e', 'penthouse', 'sale', 'active', 6200000, 'EUR', 3, 3, 198, 7, 1928,
 'Penthouse with a planted roof terrace above the 7e',
 'The upper two floors of a 1928 building, rebuilt as a single penthouse with a 90 m² terrace, outdoor kitchen and a view that runs from the Invalides to the Tower. Three suites, a study, and a lift that opens directly into the apartment.', 'art-deco'),
(6, 'MR-106', 1, 'montmartre', 'townhouse', 'sale', 'active', 1780000, 'EUR', 4, 2, 172, null, 1911,
 'A village house with a walled garden on the north slope',
 'A rare freehold house of 172 m² over three levels, with a 60 m² walled garden, a workshop and a cellar. The house needs a considered renovation, and the price reflects it. South-facing, quiet, four minutes from Lamarck–Caulaincourt.', 'traditional'),
(7, 'MR-107', 1, 'montmartre', 'apartment', 'sale', 'under_offer', 940000, 'EUR', 2, 1, 78, 1, 1895,
 'A two-bedroom with a balcony over the rue Lepic',
 'A compact, beautifully kept apartment of 78 m² with a wrought-iron balcony, a working fireplace and a kitchen that opens to the dining room. Ideal as a pied-à-terre; the building has no lift and low charges.', 'haussmannian'),
(8, 'MR-108', 1, 'le-marais', 'apartment', 'rent', 'active', 8500, 'EUR', 3, 2, 142, 3, 1850,
 'Furnished three-bedroom on the place de Vosges',
 'A fully furnished apartment of 142 m² overlooking the arcades, available on a twelve-month lease. Three bedrooms, two bathrooms, and a reception with exposed beams. Utilities and weekly housekeeping included.', 'traditional'),
(9, 'MR-109', 1, 'saint-germain', 'apartment', 'rent', 'active', 5200, 'EUR', 2, 1.5, 96, 4, 1902,
 'A quiet two-bedroom behind the rue du Bac',
 'Fourth floor with a lift, 96 m², two bedrooms and a study. Furnished in a restrained contemporary palette; the lease includes a cellar and a parking space in the courtyard.', 'contemporary'),
(10, 'MR-110', 1, 'paris-7e', 'apartment', 'sale', 'draft', 2850000, 'EUR', 3, 2, 164, 2, 1890,
 'A Gros-Caillou apartment awaiting its next chapter',
 'A 164 m² apartment with good bones: three bedrooms, a double reception and original mouldings. Currently configured as an office; the co-ownership permits residential use. Presented as a renovation project.', 'haussmannian'),
(11, 'MR-111', 1, 'le-marais', 'apartment', 'sale', 'active', 1350000, 'EUR', 1, 1, 64, 2, 1905,
 'A one-bedroom with a courtyard studio, rue des Archives',
 'Sixty-four square metres on the second floor, plus an independent 18 m² studio across the courtyard. Ideal for a buyer who works from home or wants a guest annex. Stone, oak and quiet.', 'contemporary'),
(12, 'MR-112', 1, 'saint-germain', 'apartment', 'sale', 'active', 2280000, 'EUR', 3, 2, 132, 1, 1876,
 'Three bedrooms and a garden level on the rue de Verneuil',
 'A garden-level apartment of 132 m² with a private 35 m² terrace, three bedrooms and a generous kitchen. The building is discreet, the street is quiet, and the light is better than the floor suggests.', 'haussmannian'),
(13, 'MR-113', 1, 'montmartre', 'apartment', 'sale', 'active', 1120000, 'EUR', 2, 1, 82, 5, 1935,
 'Top-floor two-bedroom with a view to Sacré-Cœur',
 'A fifth-floor walk-up with two bedrooms, a balcony and an open view over the roofs. Renovated in 2021 with a new kitchen and bathroom; the building's staircase was restored last year.', 'minimalist'),
(14, 'MR-114', 1, 'le-marais', 'penthouse', 'sale', 'active', 3900000, 'EUR', 3, 3, 188, 6, 2018,
 'A contemporary penthouse behind a listed facade',
 'A 2018 intervention behind a protected 18th-century facade: 188 m², three suites, and a 55 m² roof terrace with an outdoor fireplace. Underfloor heating, full home automation, and a lift directly into the apartment.', 'contemporary'),
(15, 'MR-115', 1, 'paris-7e', 'apartment', 'sale', 'withdrawn', 3100000, 'EUR', 3, 2, 178, 3, 1898,
 'A Champ-de-Mars apartment, withdrawn for the season',
 'A 178 m² apartment with three bedrooms and a balcony over the avenue. Withdrawn while the owners complete a kitchen renovation; enquiries are still welcome for a private preview.', 'haussmannian'),
(16, 'MR-201', 2, 'palm-jumeirah', 'villa', 'sale', 'active', 18500000, 'AED', 5, 6, 620, null, 2016,
 'A beachfront villa on the west frond of the Palm',
 'Six hundred and twenty square metres of villa on a 1,100 m² plot, with 20 m of private beach, a 15 m pool and a landscaped garden. Five suites, staff quarters, and a garage for three cars. Fully furnished by a Milanese studio.', 'mediterranean'),
(17, 'MR-202', 2, 'palm-jumeirah', 'villa', 'sale', 'active', 24000000, 'AED', 6, 7, 780, null, 2020,
 'A signature villa with a double-height living hall',
 'A 780 m² villa on the tip of a frond, with sunset views over the Gulf and the skyline behind. Six suites, a cinema, a spa with hammam, and a 22 m infinity pool. Sold with a full furniture package.', 'contemporary'),
(18, 'MR-203', 2, 'downtown-dubai', 'penthouse', 'sale', 'active', 14500000, 'AED', 4, 5, 410, 68, 2019,
 'A four-bedroom penthouse facing the Burj Khalifa',
 'A 410 m² half-floor penthouse with a 70 m² terrace, four suites and a formal dining room. The living room is oriented to the fountain and the Tower; the building offers concierge, valet and two pools.', 'contemporary'),
(19, 'MR-204', 2, 'downtown-dubai', 'apartment', 'rent', 'active', 32000, 'AED', 3, 3, 185, 42, 2021,
 'Furnished three-bedroom with skyline views, Downtown',
 'A 185 m² furnished apartment on the 42nd floor, available on a twelve-month lease. Three bedrooms, a maid''s room, and access to the building''s gym and pool. Bills and housekeeping included.', 'minimalist'),
(20, 'MR-205', 2, 'jumeirah-bay', 'apartment', 'sale', 'active', 21500000, 'AED', 4, 4, 330, 24, 2022,
 'A Jumeirah Bay residence with a private beach club',
 'A 330 m² apartment in the island''s sculptural tower, with four bedrooms, a 40 m² loggia and sea views on two sides. Residents share a private beach club, a spa and a residents-only restaurant.', 'contemporary'),
(21, 'MR-206', 2, 'jumeirah-bay', 'villa', 'sale', 'under_offer', 27000000, 'AED', 5, 6, 690, null, 2021,
 'A low villa on the island, with a courtyard plan',
 'A 690 m² villa organised around a shaded courtyard, with five suites, a library, and a pool that runs the length of the garden. The interiors use travertine, oak and lime plaster throughout.', 'minimalist'),
(22, 'MR-207', 2, 'emirates-hills', 'mansion', 'sale', 'active', 42000000, 'AED', 7, 9, 1250, null, 2014,
 'An estate villa on the Montgomerie course',
 'A 1,250 m² mansion on a 2,400 m² plot, with seven suites, a ballroom, a cinema, a spa and staff accommodation. The garden has a 25 m pool and a pool house. Direct golf-course frontage.', 'traditional'),
(23, 'MR-208', 2, 'emirates-hills', 'villa', 'sale', 'active', 19800000, 'AED', 5, 6, 720, null, 2018,
 'A contemporary villa with a double garden',
 'A 720 m² villa with a formal front garden and a family garden behind, five suites and a large open kitchen. Solar hot water, a 20 kW PV array and a borehole for irrigation.', 'contemporary'),
(24, 'MR-209', 2, 'saadiyat', 'apartment', 'sale', 'active', 6200000, 'AED', 3, 3, 195, 9, 2020,
 'A museum-district apartment with a protected sea view',
 'A 195 m² apartment with three bedrooms, a 25 m² balcony and a view across the Saadiyat dunes to the water. The building sits inside the cultural district, five minutes from the Louvre Abu Dhabi.', 'minimalist'),
(25, 'MR-210', 2, 'saadiyat', 'villa', 'sale', 'active', 12400000, 'AED', 5, 5, 540, null, 2022,
 'A beach villa on Saadiyat with a shaded loggia',
 'A 540 m² villa with five bedrooms, a 12 m pool and direct beach access. The plan separates guest and family wings around a planted courtyard; the loggia is usable through most of the year.', 'mediterranean'),
(26, 'MR-211', 2, 'al-reem', 'apartment', 'rent', 'active', 18500, 'AED', 2, 2, 128, 31, 2019,
 'A two-bedroom on Al Reem with a promenade view',
 'A 128 m² apartment on the 31st floor with two bedrooms, a study and a balcony over the water. Available furnished or unfurnished; the building has a pool, gym and direct access to the promenade.', 'contemporary'),
(27, 'MR-212', 2, 'al-reem', 'penthouse', 'sale', 'active', 7800000, 'AED', 4, 4, 285, 45, 2021,
 'A half-floor penthouse with a 60 m² terrace',
 'Four bedrooms, a 60 m² terrace and a view that takes in the Abu Dhabi skyline and the mangroves. The kitchen is by a German studio; the apartment is offered furnished.', 'modernist'),
(28, 'MR-213', 2, 'khalifa-city', 'villa', 'sale', 'active', 4600000, 'AED', 4, 4, 380, null, 2017,
 'A family villa with a garden and a separate majlis',
 'A 380 m² villa on a 600 m² plot, with four bedrooms, a separate majlis, a maid''s room and a covered parking bay. Ten minutes from three international schools.', 'traditional'),
(29, 'MR-214', 2, 'yas-island', 'apartment', 'sale', 'active', 3400000, 'AED', 2, 2, 118, 6, 2023,
 'A marina apartment on Yas, with a berth option',
 'A 118 m² two-bedroom overlooking the marina, with a 15 m² balcony and an optional 12 m berth. New building, first occupancy, with a pool, gym and direct access to the waterfront.', 'contemporary'),
(30, 'MR-215', 2, 'yas-island', 'townhouse', 'sale', 'active', 5200000, 'AED', 3, 3.5, 265, null, 2021,
 'A three-bedroom townhouse on the water',
 'A 265 m² townhouse over three levels, with three suites, a roof terrace and a private mooring. The community has a pool, a clubhouse and a waterfront restaurant.', 'minimalist');

insert into public.properties (
  agent_id, neighborhood_id, property_type_id, reference_code, listing_type, status, price,
  currency_code, bedrooms, bathrooms, area_sqm, floor_number, year_built, address_line, location
)
select
  case when s.agent_slot = 1 then 'a0000000-0000-4000-8000-000000000001'::uuid
       else 'a0000000-0000-4000-8000-000000000002'::uuid end,
  n.id, pt.id, s.reference, s.listing_type, s.status, s.price, s.currency,
  s.bedrooms, s.bathrooms, s.area, s.floor, s.year, s.address,
  st_setsrid(st_makepoint(s.lng, s.lat), 4326)::geography
from seed_listings s
join public.neighborhoods n on n.slug = s.hood_slug
join public.property_types pt on pt.code = s.type_code;

insert into public.property_translations (property_id, locale, title, description)
select p.id, 'en', s.title, s.description
from seed_listings s join public.properties p on p.reference_code = s.reference;

insert into public.property_translations (property_id, locale, title, description)
select p.id, 'ar',
  case s.type_code
    when 'villa' then 'فيلا في ' || n.name
    when 'penthouse' then 'بنتهاوس في ' || n.name
    when 'townhouse' then 'تاون هاوس في ' || n.name
    when 'loft' then 'لوفت في ' || n.name
    else 'شقة في ' || n.name
  end,
  'عقار من اختيار ميزون، بمساحة ' || round(s.area)::text || ' متر مربع و' || s.bedrooms::text ||
  ' غرف نوم. يقع في ' || n.name || ' مع إطلالات ومواد مختارة بعناية. '
from seed_listings s
join public.properties p on p.reference_code = s.reference
join public.neighborhoods n on n.slug = s.hood_slug;

insert into public.property_images (property_id, media_kind, storage_path, alt_text, sort_order, is_cover, width, height)
select p.id, 'photo', 'seed/' || lower(p.reference_code) || '-cover.svg',
       s.title || ' — ' || n.name, 0, true, 1600, 1200
from seed_listings s
join public.properties p on p.reference_code = s.reference
join public.neighborhoods n on n.slug = s.hood_slug;

insert into public.property_images (property_id, media_kind, storage_path, alt_text, sort_order, is_cover, width, height)
select p.id, 'photo', 'seed/' || lower(p.reference_code) || '-' || g || '.svg',
       s.title || ' — interior ' || g, g, false, 1600, 1200
from seed_listings s
join public.properties p on p.reference_code = s.reference
cross join generate_series(1, 2) g;

insert into public.property_images (property_id, media_kind, storage_path, alt_text, sort_order, is_cover, width, height)
select p.id, 'floor_plan', 'seed/' || lower(p.reference_code) || '-plan.svg',
       s.title || ' — floor plan', 9, false, 1400, 1000
from seed_listings s
join public.properties p on p.reference_code = s.reference
where s.idx % 3 = 0;

insert into public.property_styles (property_id, style_id, source, confidence, is_primary)
select p.id, st.id, 'agent', 1.0, true
from seed_listings s
join public.properties p on p.reference_code = s.reference
join public.architectural_styles st on st.code = s.style_code;

insert into public.property_styles (property_id, style_id, source, confidence, is_primary)
select p.id, st.id, 'vision_ai', 0.82, false
from seed_listings s
join public.properties p on p.reference_code = s.reference
join public.architectural_styles st
  on st.code = case s.style_code
    when 'haussmannian' then 'traditional'
    when 'traditional' then 'haussmannian'
    when 'contemporary' then 'minimalist'
    when 'minimalist' then 'contemporary'
    when 'modernist' then 'brutalist'
    when 'brutalist' then 'modernist'
    when 'art-deco' then 'contemporary'
    else 'traditional'
  end;

-- Amenities: deterministic per listing, with a stable spread across categories.
insert into public.property_amenities (property_id, amenity_id)
select p.id, a.id
from seed_listings s
join public.properties p on p.reference_code = s.reference
join public.amenities a on a.code in (
  case when s.idx % 4 = 0 then 'pool' when s.idx % 4 = 1 then 'spa' when s.idx % 4 = 2 then 'gym' else 'hammam' end,
  case when s.idx % 3 = 0 then 'terrace' when s.idx % 3 = 1 then 'garden' else 'balcony' end,
  case when s.idx % 2 = 0 then 'home-automation' else 'climate-control' end,
  case when s.listing_type = 'sale' then 'concierge' else 'elevator' end,
  case when s.currency = 'EUR' then 'fireplace' else 'parking' end,
  case when s.hood_slug in ('palm-jumeirah','jumeirah-bay','saadiyat','yas-island') then 'sea-view'
       when s.hood_slug in ('downtown-dubai','al-reem') then 'skyline-view'
       else 'city-view' end
)
on conflict do nothing;

insert into public.property_price_history (property_id, price, changed_by, changed_at)
select p.id, p.price, p.agent_id, p.created_at - interval '60 days'
from public.properties p where p.reference_code like 'MR-%';

insert into public.property_price_history (property_id, price, changed_by, changed_at)
select p.id, round(p.price * 0.94, 2), p.agent_id, now() - interval '12 days'
from public.properties p
where p.reference_code like 'MR-%' and p.status in ('active', 'under_offer');

-- ── Deterministic taste embeddings (1536-d, style-coherent) ────────────────
update public.properties p
set embedding = sub.v,
    embedding_stale = false
from (
  select ps.property_id,
         (select array_agg(
            sin(i * 0.013 + (abs(hashtext(st.code)) % 89) * 0.071) * 0.8
            + cos(i * 0.007 + (abs(hashtext(ps.property_id::text)) % 13)) * 0.2
          )::vector(1536)
          from generate_series(1, 1536) i) as v
  from public.property_styles ps
  join public.architectural_styles st on st.id = ps.style_id
  where ps.is_primary
) sub
where p.id = sub.property_id;

-- ── Demo preferences for Élise ─────────────────────────────────────────────
insert into public.consent_records (profile_id, consent_type, policy_version, granted_at)
values ('b0000000-0000-4000-8000-000000000001', 'profiling', '2026-02-01', now() - interval '30 days')
on conflict do nothing;

insert into public.consent_records (profile_id, consent_type, policy_version, granted_at)
values ('b0000000-0000-4000-8000-000000000001', 'ai_processing', '2026-02-01', now() - interval '30 days')
on conflict do nothing;

update public.client_preferences set
  listing_type = 'sale',
  currency_code = 'EUR',
  budget_min = 1800000,
  budget_max = 3200000,
  min_bedrooms = 3,
  min_bathrooms = 2,
  min_area_sqm = 140,
  personalization_enabled = true
where client_id = 'b0000000-0000-4000-8000-000000000001';

insert into public.preference_styles (client_id, style_id, score) values
  ('b0000000-0000-4000-8000-000000000001', '33333333-3333-4333-8333-333333333301', 2),
  ('b0000000-0000-4000-8000-000000000001', '33333333-3333-4333-8333-333333333302', 1),
  ('b0000000-0000-4000-8000-000000000001', '33333333-3333-4333-8333-333333333304', -1)
on conflict (client_id, style_id) do nothing;

insert into public.preference_amenities (client_id, amenity_id, requirement)
select 'b0000000-0000-4000-8000-000000000001', id,
       case when code in ('concierge', 'elevator') then 'must'::public.requirement_level
            else 'nice'::public.requirement_level end
from public.amenities
where code in ('concierge', 'elevator', 'terrace', 'fireplace', 'wine-cellar')
on conflict do nothing;

insert into public.preference_neighborhoods (client_id, neighborhood_id, priority) values
  ('b0000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222201', 3),
  ('b0000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222202', 2),
  ('b0000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222203', 1)
on conflict do nothing;

insert into public.preference_property_types (client_id, property_type_id) values
  ('b0000000-0000-4000-8000-000000000001', '55555555-5555-4555-8555-555555555501'),
  ('b0000000-0000-4000-8000-000000000001', '55555555-5555-4555-8555-555555555502')
on conflict do nothing;

insert into public.preference_updates
  (client_id, origin, field_path, proposed_value, previous_value, confidence, reason, status, created_at, resolved_at)
values
  ('b0000000-0000-4000-8000-000000000001', 'chat', 'min_bedrooms', '4'::jsonb, '3'::jsonb, 0.72,
   'You mentioned a guest room on the left bank.', 'pending', now() - interval '2 hours', null),
  ('b0000000-0000-4000-8000-000000000001', 'chat', 'budget_max', '3600000'::jsonb, '3200000'::jsonb, 0.64,
   'You asked whether the upper range could stretch for the right apartment.', 'pending', now() - interval '2 hours', null);

insert into public.collections (id, client_id, name, is_default) values
  ('77777777-7777-4777-8777-777777777701', 'b0000000-0000-4000-8000-000000000001', 'Paris, in confidence', true)
on conflict (id) do nothing;

insert into public.collection_items (collection_id, property_id, note)
select '77777777-7777-4777-8777-777777777701', p.id,
       case p.reference_code
         when 'MR-101' then 'The enfilade is extraordinary. Ask about the cellar.'
         when 'MR-103' then 'Library light in the afternoon — worth a second visit.'
         when 'MR-104' then 'Tower view, but the service kitchen is small.'
         else 'Saved from the advisor.'
       end
from public.properties p
where p.reference_code in ('MR-101', 'MR-103', 'MR-104', 'MR-112');

-- ── Engagement: viewings, inquiries, notifications ─────────────────────────
insert into public.viewing_requests
  (client_id, property_id, agent_id, requested_start, duration_minutes, status, notes)
select 'b0000000-0000-4000-8000-000000000001', p.id, p.agent_id,
       date_trunc('day', now()) + interval '3 days 11 hours', 45, 'confirmed',
       'I would like to see the courtyard and the cellar.'
from public.properties p where p.reference_code = 'MR-101';

insert into public.viewing_requests
  (client_id, property_id, agent_id, requested_start, duration_minutes, status, notes)
select 'b0000000-0000-4000-8000-000000000001', p.id, p.agent_id,
       date_trunc('day', now()) + interval '5 days 15 hours 30 minutes', 45, 'requested',
       'Could we meet at the building entrance?'
from public.properties p where p.reference_code = 'MR-103';

insert into public.inquiries (id, client_id, property_id, subject, status) values
  ('88888888-8888-4888-8888-888888888801', 'b0000000-0000-4000-8000-000000000001',
   (select id from public.properties where reference_code = 'MR-104'),
   'Service charges and the service kitchen', 'open')
on conflict (id) do nothing;

insert into public.inquiry_messages (inquiry_id, sender_id, body, created_at) values
  ('88888888-8888-4888-8888-888888888801', 'b0000000-0000-4000-8000-000000000001',
   'Could you send the last three years of service charges, and confirm whether the service kitchen can be opened to the dining room?', now() - interval '1 day'),
  ('88888888-8888-4888-8888-888888888801', 'a0000000-0000-4000-8000-000000000001',
   'Of course. Charges have averaged €8,400 a year including the concierge. The wall is not load-bearing and two owners on the same floor have already done exactly that — I can send the approved plan.', now() - interval '20 hours');

insert into public.conversations (id, client_id, title, summary) values
  ('99999999-9999-4999-8999-999999999901', 'b0000000-0000-4000-8000-000000000001',
   'Left bank, four bedrooms, light',
   'Client prefers Haussmannian apartments on the left bank, budget €1.8–3.2M, needs at least three bedrooms and a concierge.')
on conflict (id) do nothing;

insert into public.messages (id, conversation_id, role, content, created_at) values
  ('99999999-9999-4999-8999-999999999911', '99999999-9999-4999-8999-999999999901', 'user',
   'I keep coming back to the Marais. Something with real rooms, not a white box — and I would rather have light than a second bathroom.', now() - interval '2 days'),
  ('99999999-9999-4999-8999-999999999912', '99999999-9999-4999-8999-999999999901', 'assistant',
   'Then I would start with the Sévigné apartment. It has the enfilade and the garden windows you described, and the kitchen was rebuilt without losing the proportions. There are two others worth your time: a full-floor on La Bourdonnais with the Tower in every window, and the Verneuil garden level if you would trade altitude for a terrace.', now() - interval '2 days')
on conflict (id) do nothing;

-- Keep the demo conversation aligned with the listing references.
insert into public.tool_calls (message_id, tool_name, arguments, result, status, duration_ms)
values ('99999999-9999-4999-8999-999999999912', 'search_properties',
  '{"listing_type":"sale","neighborhoods":["le-marais","saint-germain"],"min_bedrooms":3}'::jsonb,
  '{"count":3,"references":["MR-101","MR-103","MR-104"]}'::jsonb, 'success', 412)
on conflict do nothing;

-- Recompute the demo version so every cached surface starts fresh.
update public.client_preferences set profile_version = profile_version + 1
where client_id = 'b0000000-0000-4000-8000-000000000001';

analyze public.properties;
analyze public.listing_cards;

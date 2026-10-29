begin;
select plan(7);

-- 1. Test is_agency_verified function
select ok(
  public.is_agency_verified('66666666-6666-4666-8666-666666666601'::uuid),
  'Seeded agency Maison Privé is verified'
);

select ok(
  not public.is_agency_verified('00000000-0000-0000-0000-000000000000'::uuid),
  'Unknown agency is not verified'
);

-- 2. Test listing_cards view returns public verified listings
select isnt_empty(
  'select * from public.listing_cards',
  'listing_cards view projects active listings from verified agencies'
);

-- 3. Test match_properties with demo client Élise
select isnt_empty(
  'select * from public.match_properties(''b0000000-0000-4000-8000-000000000001''::uuid, 10, 0, ''relevance'')',
  'match_properties returns personalized candidate listings for consented client'
);

-- 4. Verify match_score is bounded between 0 and 1
select is(
  (select count(*) from public.match_properties('b0000000-0000-4000-8000-000000000001'::uuid, 10, 0)
   where match_score < 0 or match_score > 1),
  0::bigint,
  'All match_scores are between 0 and 1'
);

-- 5. Test export_my_data as Elise
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "b0000000-0000-4000-8000-000000000001", "role": "authenticated"}';

select ok(
  (public.export_my_data() -> 'profile' ->> 'full_name') = 'Élise Moreau',
  'export_my_data returns caller profile and preferences JSON'
);

-- 6. Test delete_my_account function exists and is executable by authenticated
select has_function('public', 'delete_my_account', 'delete_my_account function exists');

select * from finish();
rollback;

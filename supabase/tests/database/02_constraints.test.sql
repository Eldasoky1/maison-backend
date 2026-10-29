begin;
select plan(5);

-- 1. Check composite unique constraint on properties(id, agent_id)
select col_is_unique(
  'public', 'properties',
  array['id', 'agent_id'],
  'properties has unique constraint on (id, agent_id)'
);

-- 2. Test price check constraint on properties (price > 0)
prepare bad_price as insert into public.properties (
  agent_id, neighborhood_id, property_type_id, reference_code,
  listing_type, price, currency_code, area_sqm, address_line, location
) values (
  'a0000000-0000-4000-8000-000000000001'::uuid,
  '22222222-2222-4222-8222-222222222201'::uuid,
  '55555555-5555-4555-8555-555555555501'::uuid,
  'FAIL-PRICE',
  'sale',
  -100,
  'EUR',
  120,
  'Test',
  st_setsrid(st_makepoint(2.35, 48.85), 4326)::geography
);
select throws_ok('bad_price', '23514', null, 'price > 0 constraint is enforced');

-- 3. Test preference_styles score constraint (between -2 and 2 and score <> 0)
prepare bad_score as insert into public.preference_styles (
  client_id, style_id, score
) values (
  'b0000000-0000-4000-8000-000000000001'::uuid,
  '33333333-3333-4333-8333-333333333306'::uuid,
  0
);
select throws_ok('bad_score', '23514', null, 'preference_styles score <> 0 constraint is enforced');

-- 4. Test notifications constraint: exactly one subject set
prepare bad_notif as insert into public.notifications (
  recipient_id, type, property_id, inquiry_id, body
) values (
  'b0000000-0000-4000-8000-000000000001'::uuid,
  'system',
  (select id from public.properties limit 1),
  '88888888-8888-4888-8888-888888888801'::uuid,
  'Invalid notification with two subjects'
);
select throws_ok('bad_notif', '23514', null, 'notifications num_nonnulls = 1 constraint is enforced');

-- 5. Test viewing_requests GiST exclusion constraint (overlapping slots for same agent)
prepare overlap_viewing as insert into public.viewing_requests (
  client_id, property_id, agent_id, requested_start, duration_minutes, status
) select
  'b0000000-0000-4000-8000-000000000002'::uuid,
  vr.property_id,
  vr.agent_id,
  vr.requested_start + interval '10 minutes',
  vr.duration_minutes,
  'confirmed'
from public.viewing_requests vr
where vr.status = 'confirmed'
limit 1;

select throws_ok('overlap_viewing', '23P01', null, 'viewing_requests GiST exclusion constraint prevents overlapping bookings');

select * from finish();
rollback;

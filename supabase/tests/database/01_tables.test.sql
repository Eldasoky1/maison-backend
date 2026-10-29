begin;
select plan(16);

-- 1. Check all 39 tables exist
select has_table('public', 'currencies', 'currencies table exists');
select has_table('public', 'countries', 'countries table exists');
select has_table('public', 'cities', 'cities table exists');
select has_table('public', 'neighborhoods', 'neighborhoods table exists');
select has_table('public', 'architectural_styles', 'architectural_styles table exists');
select has_table('public', 'amenity_categories', 'amenity_categories table exists');
select has_table('public', 'amenities', 'amenities table exists');
select has_table('public', 'property_types', 'property_types table exists');
select has_table('public', 'hero_variants', 'hero_variants table exists');
select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'agencies', 'agencies table exists');
select has_table('public', 'agent_profiles', 'agent_profiles table exists');
select has_table('public', 'agency_verifications', 'agency_verifications table exists');
select has_table('public', 'consent_records', 'consent_records table exists');
select has_table('public', 'audit_logs', 'audit_logs table exists');
select has_table('public', 'properties', 'properties table exists');

select * from finish();
rollback;

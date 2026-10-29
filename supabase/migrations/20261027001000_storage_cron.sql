-- 0010 — Storage buckets, storage policies, retention jobs.

set search_path = public, extensions;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('property-images', 'property-images', true, 15728640, array['image/jpeg','image/png','image/webp','image/avif','image/svg+xml']),
  ('avatars', 'avatars', true, 2097152, array['image/jpeg','image/png','image/webp']),
  ('agency-documents', 'agency-documents', false, 10485760, array['application/pdf','image/jpeg','image/png'])
on conflict (id) do nothing;

-- Public buckets: anyone may read; writes are folder-scoped to the owner.
drop policy if exists "public media read" on storage.objects;
create policy "public media read" on storage.objects
  for select to anon, authenticated
  using (bucket_id in ('property-images', 'avatars'));

drop policy if exists "avatars write own folder" on storage.objects;
create policy "avatars write own folder" on storage.objects
  for all to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "property images agent write" on storage.objects;
create policy "property images agent write" on storage.objects
  for all to authenticated
  using (
    bucket_id = 'property-images'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
    )
  )
  with check (
    bucket_id = 'property-images'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
    )
  );

-- Agency documents: only the submitting agency's members and admins.
drop policy if exists "agency documents read" on storage.objects;
create policy "agency documents read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'agency-documents'
    and (
      public.is_admin()
      or exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.agency_id::text = (storage.foldername(name))[1]
      )
    )
  );

drop policy if exists "agency documents write" on storage.objects;
create policy "agency documents write" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'agency-documents'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.agency_id::text = (storage.foldername(name))[1]
    )
  );

-- ── Retention ───────────────────────────────────────────────────────────────
create or replace function public.purge_expired_data()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  delete from public.property_interactions where occurred_at < now() - interval '180 days';
  delete from public.llm_calls where created_at < now() - interval '365 days';
  delete from public.tool_calls where created_at < now() - interval '365 days';
  delete from public.notifications where created_at < now() - interval '180 days';
  update public.agency_verifications
     set status = 'expired'
   where status = 'approved' and expires_at is not null and expires_at < now();
end;
$$;

revoke all on function public.purge_expired_data() from public;
grant execute on function public.purge_expired_data() to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'maison-purge-expired') then
      perform cron.unschedule((select jobid from cron.job where jobname = 'maison-purge-expired'));
    end if;
    perform cron.schedule('maison-purge-expired', '15 3 * * *', 'select public.purge_expired_data()');
  else
    raise notice 'pg_cron not installed — schedule purge_expired_data() manually';
  end if;
exception when others then
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end $$;

-- ── Data export helper used by /account/privacy ─────────────────────────────
create or replace function public.export_my_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.id = v_uid),
    'preferences', (select to_jsonb(cp) from public.client_preferences cp where cp.client_id = v_uid),
    'preference_styles', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.preference_styles x where x.client_id = v_uid),
    'preference_amenities', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.preference_amenities x where x.client_id = v_uid),
    'preference_neighborhoods', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.preference_neighborhoods x where x.client_id = v_uid),
    'preference_property_types', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.preference_property_types x where x.client_id = v_uid),
    'collections', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.collections x where x.client_id = v_uid),
    'viewings', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.viewing_requests x where x.client_id = v_uid),
    'inquiries', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.inquiries x where x.client_id = v_uid),
    'consents', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.consent_records x where x.profile_id = v_uid),
    'conversations', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.conversations x where x.client_id = v_uid)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.export_my_data() from public;
grant execute on function public.export_my_data() to authenticated;

-- ── Data erasure helper used by /account/privacy (GDPR Article 17) ─────────
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  -- Delete from auth.users which cascades to profiles, client_preferences,
  -- preference child tables, collections, viewing_requests, inquiries,
  -- conversations, and consent records.
  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;


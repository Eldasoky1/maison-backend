-- 0009 — Row Level Security. Every table is protected; the public projections in
-- 0008 are the only deliberate RLS-bypassing read paths.

set search_path = public, extensions;

alter table public.currencies enable row level security;
alter table public.countries enable row level security;
alter table public.cities enable row level security;
alter table public.neighborhoods enable row level security;
alter table public.architectural_styles enable row level security;
alter table public.amenity_categories enable row level security;
alter table public.amenities enable row level security;
alter table public.property_types enable row level security;
alter table public.hero_variants enable row level security;
alter table public.agencies enable row level security;
alter table public.profiles enable row level security;
alter table public.agent_profiles enable row level security;
alter table public.agency_verifications enable row level security;
alter table public.consent_records enable row level security;
alter table public.audit_logs enable row level security;
alter table public.properties enable row level security;
alter table public.property_translations enable row level security;
alter table public.property_images enable row level security;
alter table public.property_amenities enable row level security;
alter table public.property_styles enable row level security;
alter table public.property_price_history enable row level security;
alter table public.client_preferences enable row level security;
alter table public.preference_styles enable row level security;
alter table public.preference_amenities enable row level security;
alter table public.preference_neighborhoods enable row level security;
alter table public.preference_property_types enable row level security;
alter table public.preference_updates enable row level security;
alter table public.collections enable row level security;
alter table public.collection_items enable row level security;
alter table public.property_interactions enable row level security;
alter table public.agent_availability enable row level security;
alter table public.viewing_requests enable row level security;
alter table public.inquiries enable row level security;
alter table public.inquiry_messages enable row level security;
alter table public.notifications enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.tool_calls enable row level security;
alter table public.llm_calls enable row level security;

-- ── Reference data: readable by everyone, writable by admins ───────────────
do $$
declare
  t text;
begin
  foreach t in array array[
    'currencies', 'countries', 'cities', 'neighborhoods', 'architectural_styles',
    'amenity_categories', 'amenities', 'property_types', 'hero_variants'
  ] loop
    execute format('drop policy if exists "reference read" on public.%I', t);
    execute format(
      'create policy "reference read" on public.%I for select to anon, authenticated using (true)', t);
    execute format('drop policy if exists "reference admin write" on public.%I', t);
    execute format(
      'create policy "reference admin write" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

-- ── Agencies ────────────────────────────────────────────────────────────────
drop policy if exists "agencies read" on public.agencies;
create policy "agencies read" on public.agencies
  for select to anon, authenticated using (true);

drop policy if exists "agencies update members" on public.agencies;
create policy "agencies update members" on public.agencies
  for update to authenticated
  using (
    public.is_admin() or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.agency_id = agencies.id and p.role in ('agent', 'admin')
    )
  )
  with check (
    public.is_admin() or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.agency_id = agencies.id and p.role in ('agent', 'admin')
    )
  );

drop policy if exists "agencies admin insert" on public.agencies;
create policy "agencies admin insert" on public.agencies
  for insert to authenticated with check (public.is_admin());

-- ── Profiles ────────────────────────────────────────────────────────────────
-- Rows: own row, public agent directory rows, or admin.
drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles
  for select to anon, authenticated
  using (id = auth.uid() or role in ('agent', 'admin') or public.is_admin());

drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

drop policy if exists "profiles insert own" on public.profiles;
create policy "profiles insert own" on public.profiles
  for insert to authenticated with check (id = auth.uid());

-- Column privileges: anon may never read a private phone number. Agents publish
-- agent_profiles.public_phone instead. Users may never change their own role or
-- agency — those columns are service-role only.
revoke select on public.profiles from anon;
grant select (id, role, agency_id, full_name, avatar_path, is_anonymous, locale, created_at, updated_at)
  on public.profiles to anon;
grant select on public.profiles to authenticated;
revoke insert, update on public.profiles from anon, authenticated;
grant update (full_name, phone, avatar_path, locale) on public.profiles to authenticated;

-- ── Agent profiles ──────────────────────────────────────────────────────────
drop policy if exists "agent profiles read" on public.agent_profiles;
create policy "agent profiles read" on public.agent_profiles
  for select to anon, authenticated using (true);

drop policy if exists "agent profiles write own" on public.agent_profiles;
create policy "agent profiles write own" on public.agent_profiles
  for all to authenticated
  using (profile_id = auth.uid() or public.is_admin())
  with check (profile_id = auth.uid() or public.is_admin());

-- ── Agency verifications ────────────────────────────────────────────────────
drop policy if exists "verifications read" on public.agency_verifications;
create policy "verifications read" on public.agency_verifications
  for select to authenticated
  using (
    public.is_admin()
    or submitted_by = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.agency_id = agency_verifications.agency_id
    )
  );

drop policy if exists "verifications submit" on public.agency_verifications;
create policy "verifications submit" on public.agency_verifications
  for insert to authenticated
  with check (
    submitted_by = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.agency_id = agency_verifications.agency_id
    )
  );

drop policy if exists "verifications review" on public.agency_verifications;
create policy "verifications review" on public.agency_verifications
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ── Consent and audit ───────────────────────────────────────────────────────
drop policy if exists "consent read own" on public.consent_records;
create policy "consent read own" on public.consent_records
  for select to authenticated using (profile_id = auth.uid() or public.is_admin());

drop policy if exists "consent write own" on public.consent_records;
create policy "consent write own" on public.consent_records
  for insert to authenticated with check (profile_id = auth.uid());

drop policy if exists "consent revoke own" on public.consent_records;
create policy "consent revoke own" on public.consent_records
  for update to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

drop policy if exists "audit admin read" on public.audit_logs;
create policy "audit admin read" on public.audit_logs
  for select to authenticated using (public.is_admin());

drop policy if exists "audit admin insert" on public.audit_logs;
create policy "audit admin insert" on public.audit_logs
  for insert to authenticated with check (public.is_admin());

-- ── Properties ──────────────────────────────────────────────────────────────
-- Public: live listings whose agency is verified. Agents: their own. Admins: all.
drop policy if exists "properties read" on public.properties;
create policy "properties read" on public.properties
  for select to anon, authenticated
  using (
    agent_id = auth.uid()
    or public.is_admin()
    or (
      status in ('active', 'under_offer')
      and exists (
        select 1 from public.profiles p
        where p.id = properties.agent_id
          and p.agency_id is not null
          and public.is_agency_verified(p.agency_id)
      )
    )
  );

drop policy if exists "properties agent insert" on public.properties;
create policy "properties agent insert" on public.properties
  for insert to authenticated
  with check (agent_id = auth.uid() and public.is_agent());

drop policy if exists "properties agent update" on public.properties;
create policy "properties agent update" on public.properties
  for update to authenticated
  using (agent_id = auth.uid() or public.is_admin())
  with check (agent_id = auth.uid() or public.is_admin());

drop policy if exists "properties agent delete" on public.properties;
create policy "properties agent delete" on public.properties
  for delete to authenticated
  using ((agent_id = auth.uid() and status = 'draft') or public.is_admin());

-- ── Property children ───────────────────────────────────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array[
    'property_translations', 'property_images', 'property_amenities',
    'property_styles', 'property_price_history'
  ] loop
    execute format('drop policy if exists "property child read" on public.%I', t);
    execute format($f$
      create policy "property child read" on public.%I
        for select to anon, authenticated
        using (exists (select 1 from public.properties p where p.id = %I.property_id))
    $f$, t, t);

    execute format('drop policy if exists "property child write" on public.%I', t);
    execute format($f$
      create policy "property child write" on public.%I
        for all to authenticated
        using (exists (
          select 1 from public.properties p
          where p.id = %I.property_id and (p.agent_id = auth.uid() or public.is_admin())
        ))
        with check (exists (
          select 1 from public.properties p
          where p.id = %I.property_id and (p.agent_id = auth.uid() or public.is_admin())
        ))
    $f$, t, t, t);
  end loop;
end $$;

-- ── Preferences ─────────────────────────────────────────────────────────────
drop policy if exists "preferences own" on public.client_preferences;
create policy "preferences own" on public.client_preferences
  for all to authenticated
  using (client_id = auth.uid() or public.is_admin())
  with check (client_id = auth.uid() or public.is_admin());

do $$
declare
  t text;
begin
  foreach t in array array[
    'preference_styles', 'preference_amenities', 'preference_neighborhoods',
    'preference_property_types', 'preference_updates'
  ] loop
    execute format('drop policy if exists "preference rows own" on public.%I', t);
    execute format($f$
      create policy "preference rows own" on public.%I
        for all to authenticated
        using (client_id = auth.uid() or public.is_admin())
        with check (client_id = auth.uid() or public.is_admin())
    $f$, t);
  end loop;
end $$;

-- ── Collections ─────────────────────────────────────────────────────────────
drop policy if exists "collections own" on public.collections;
create policy "collections own" on public.collections
  for all to authenticated
  using (client_id = auth.uid() or public.is_admin())
  with check (client_id = auth.uid() or public.is_admin());

drop policy if exists "collection items own" on public.collection_items;
create policy "collection items own" on public.collection_items
  for all to authenticated
  using (exists (
    select 1 from public.collections c
    where c.id = collection_items.collection_id
      and (c.client_id = auth.uid() or public.is_admin())
  ))
  with check (exists (
    select 1 from public.collections c
    where c.id = collection_items.collection_id
      and (c.client_id = auth.uid() or public.is_admin())
  ));

-- ── Interactions ────────────────────────────────────────────────────────────
drop policy if exists "interactions insert own" on public.property_interactions;
create policy "interactions insert own" on public.property_interactions
  for insert to authenticated with check (client_id = auth.uid());

drop policy if exists "interactions read own" on public.property_interactions;
create policy "interactions read own" on public.property_interactions
  for select to authenticated using (client_id = auth.uid() or public.is_admin());

-- ── Availability ────────────────────────────────────────────────────────────
drop policy if exists "availability read" on public.agent_availability;
create policy "availability read" on public.agent_availability
  for select to anon, authenticated using (true);

drop policy if exists "availability manage own" on public.agent_availability;
create policy "availability manage own" on public.agent_availability
  for all to authenticated
  using (agent_id = auth.uid() or public.is_admin())
  with check (agent_id = auth.uid() or public.is_admin());

-- ── Viewing requests ────────────────────────────────────────────────────────
drop policy if exists "viewings read" on public.viewing_requests;
create policy "viewings read" on public.viewing_requests
  for select to authenticated
  using (client_id = auth.uid() or agent_id = auth.uid() or public.is_admin());

drop policy if exists "viewings client insert" on public.viewing_requests;
create policy "viewings client insert" on public.viewing_requests
  for insert to authenticated
  with check (client_id = auth.uid());

drop policy if exists "viewings update participants" on public.viewing_requests;
create policy "viewings update participants" on public.viewing_requests
  for update to authenticated
  using (client_id = auth.uid() or agent_id = auth.uid() or public.is_admin())
  with check (client_id = auth.uid() or agent_id = auth.uid() or public.is_admin());

-- ── Inquiries ───────────────────────────────────────────────────────────────
drop policy if exists "inquiries read participants" on public.inquiries;
create policy "inquiries read participants" on public.inquiries
  for select to authenticated
  using (
    client_id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.properties p
      where p.id = inquiries.property_id and p.agent_id = auth.uid()
    )
  );

drop policy if exists "inquiries client insert" on public.inquiries;
create policy "inquiries client insert" on public.inquiries
  for insert to authenticated with check (client_id = auth.uid());

drop policy if exists "inquiries participants update" on public.inquiries;
create policy "inquiries participants update" on public.inquiries
  for update to authenticated
  using (
    client_id = auth.uid()
    or public.is_admin()
    or exists (select 1 from public.properties p where p.id = inquiries.property_id and p.agent_id = auth.uid())
  )
  with check (
    client_id = auth.uid()
    or public.is_admin()
    or exists (select 1 from public.properties p where p.id = inquiries.property_id and p.agent_id = auth.uid())
  );

drop policy if exists "inquiry messages read participants" on public.inquiry_messages;
create policy "inquiry messages read participants" on public.inquiry_messages
  for select to authenticated
  using (exists (
    select 1 from public.inquiries i
    join public.properties p on p.id = i.property_id
    where i.id = inquiry_messages.inquiry_id
      and (i.client_id = auth.uid() or p.agent_id = auth.uid() or public.is_admin())
  ));

drop policy if exists "inquiry messages insert participants" on public.inquiry_messages;
create policy "inquiry messages insert participants" on public.inquiry_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.inquiries i
      join public.properties p on p.id = i.property_id
      where i.id = inquiry_messages.inquiry_id
        and (i.client_id = auth.uid() or p.agent_id = auth.uid())
    )
  );

drop policy if exists "inquiry messages mark read" on public.inquiry_messages;
create policy "inquiry messages mark read" on public.inquiry_messages
  for update to authenticated
  using (exists (
    select 1 from public.inquiries i
    join public.properties p on p.id = i.property_id
    where i.id = inquiry_messages.inquiry_id
      and (i.client_id = auth.uid() or p.agent_id = auth.uid())
  ))
  with check (true);

-- ── Notifications ───────────────────────────────────────────────────────────
drop policy if exists "notifications own" on public.notifications;
create policy "notifications own" on public.notifications
  for select to authenticated using (recipient_id = auth.uid());

drop policy if exists "notifications mark read" on public.notifications;
create policy "notifications mark read" on public.notifications
  for update to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

-- ── AI ──────────────────────────────────────────────────────────────────────
drop policy if exists "conversations own" on public.conversations;
create policy "conversations own" on public.conversations
  for all to authenticated
  using (client_id = auth.uid() or public.is_admin())
  with check (client_id = auth.uid() or public.is_admin());

drop policy if exists "messages own" on public.messages;
create policy "messages own" on public.messages
  for select to authenticated
  using (exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
      and (c.client_id = auth.uid() or public.is_admin())
  ));

drop policy if exists "tool calls own" on public.tool_calls;
create policy "tool calls own" on public.tool_calls
  for select to authenticated
  using (exists (
    select 1 from public.messages m
    join public.conversations c on c.id = m.conversation_id
    where m.id = tool_calls.message_id
      and (c.client_id = auth.uid() or public.is_admin())
  ));

drop policy if exists "llm calls admin read" on public.llm_calls;
create policy "llm calls admin read" on public.llm_calls
  for select to authenticated using (public.is_admin());

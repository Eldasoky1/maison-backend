-- 0001 — Extensions, enumerated types and shared helpers
-- Maison v2. Every object is created idempotently so the migration can be replayed
-- on a fresh local database or pushed to a hosted project.

set search_path = public, extensions;

create schema if not exists extensions;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists postgis with schema extensions;
create extension if not exists vector with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists btree_gist with schema extensions;

-- ── Enumerated types ────────────────────────────────────────────────────────
do $$ begin
  create type public.user_role as enum ('client', 'agent', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.listing_type as enum ('sale', 'rent');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.listing_status as enum ('draft', 'active', 'under_offer', 'closed', 'withdrawn');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.media_kind as enum ('photo', 'floor_plan');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.style_source as enum ('agent', 'vision_ai', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.requirement_level as enum ('must', 'nice');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.preference_origin as enum ('chat', 'quiz', 'manual');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.preference_status as enum ('pending', 'applied', 'rejected', 'superseded');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.interaction_type as enum ('view', 'gallery_open', 'contact_click', 'dismiss');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.viewing_status as enum ('requested', 'confirmed', 'declined', 'completed', 'cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.inquiry_status as enum ('open', 'closed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.message_role as enum ('user', 'assistant');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tool_status as enum ('success', 'error');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.llm_feature as enum ('chat', 'extraction', 'summary', 'embedding', 'vision_tagging');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.llm_status as enum ('success', 'error');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.verification_status as enum ('pending', 'approved', 'rejected', 'expired');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.consent_type as enum ('profiling', 'ai_processing', 'marketing');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.conversation_status as enum ('active', 'archived');
exception when duplicate_object then null; end $$;

-- ── Shared trigger: touch updated_at ────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ── Shared trigger: guard that a row belongs to the caller ──────────────────
create or replace function public.assert_owner(p_owner uuid)
returns void
language plpgsql
set search_path = public, extensions
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_owner <> auth.uid() and not public.is_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
end;
$$;

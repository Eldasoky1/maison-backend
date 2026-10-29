-- 0005 — AI conversation domain.

set search_path = public, extensions;

create table if not exists public.conversations (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references public.profiles(id) on delete cascade,
  title      text not null default 'New conversation',
  status     public.conversation_status not null default 'active',
  summary    text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists conversations_client_idx
  on public.conversations (client_id, updated_at desc);

create table if not exists public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  role            public.message_role not null,
  content         text not null,
  created_at      timestamptz not null default now()
);

create index if not exists messages_conversation_idx
  on public.messages (conversation_id, created_at);

create table if not exists public.tool_calls (
  id          uuid primary key default gen_random_uuid(),
  message_id  uuid not null references public.messages(id) on delete cascade,
  tool_name   text not null,
  arguments   jsonb not null default '{}'::jsonb,
  result      jsonb,
  status      public.tool_status not null default 'success',
  duration_ms integer,
  created_at  timestamptz not null default now()
);

create index if not exists tool_calls_message_idx on public.tool_calls (message_id);
create index if not exists tool_calls_name_idx on public.tool_calls (tool_name, created_at desc);

create table if not exists public.llm_calls (
  id                uuid primary key default gen_random_uuid(),
  message_id        uuid references public.messages(id) on delete set null,
  feature           public.llm_feature not null,
  model_id          text not null,
  prompt_tokens     integer not null default 0,
  completion_tokens integer not null default 0,
  cost_usd          numeric(10, 6) not null default 0,
  latency_ms        integer,
  status            public.llm_status not null default 'success',
  created_at        timestamptz not null default now()
);

create index if not exists llm_calls_created_idx on public.llm_calls (created_at desc);
create index if not exists llm_calls_feature_idx on public.llm_calls (feature, created_at desc);

create or replace trigger conversations_touch_updated_at
  before update on public.conversations
  for each row execute function public.set_updated_at();

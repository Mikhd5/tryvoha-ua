-- ТРИВОГА.UA initial schema
-- Apply with Supabase CLI: supabase db push
-- No live alert ingestion is enabled by this migration.

create extension if not exists pgcrypto;

create type public.alert_status as enum ('draft', 'published', 'withdrawn');
create type public.alert_severity as enum ('info', 'watch', 'warning', 'critical');
create type public.news_status as enum ('draft', 'published', 'archived');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  preferred_language text not null default 'uk' check (preferred_language in ('uk', 'en', 'sv')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cities (
  id uuid primary key default gen_random_uuid(),
  country_code char(2) not null default 'UA',
  name text not null,
  region_name text,
  slug text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.user_city_subscriptions (
  user_id uuid not null references auth.users(id) on delete cascade,
  city_id uuid not null references public.cities(id) on delete cascade,
  notify_push boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (user_id, city_id)
);

create table public.alert_sources (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  publisher text not null,
  source_url text not null,
  source_type text not null check (source_type in ('official_api', 'official_feed', 'manual_verified')),
  is_enabled boolean not null default false,
  last_success_at timestamptz,
  last_error_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  constraint alert_sources_url_https check (source_url like 'https://%')
);

create table public.alert_events (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.alert_sources(id),
  city_id uuid references public.cities(id),
  region_name text not null,
  city_name text,
  event_type text not null,
  severity public.alert_severity not null,
  title text not null,
  body text,
  source_url text not null,
  external_id text,
  status public.alert_status not null default 'draft',
  occurred_at timestamptz not null,
  verified_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  unique (source_id, external_id),
  constraint alert_events_source_https check (source_url like 'https://%')
);

create index alert_events_published_time_idx
  on public.alert_events (occurred_at desc)
  where status = 'published';
create index alert_events_city_time_idx
  on public.alert_events (city_id, occurred_at desc)
  where status = 'published';

create table public.news_articles (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  summary text,
  language text not null default 'uk',
  source_name text not null,
  source_url text not null,
  published_at timestamptz not null,
  status public.news_status not null default 'draft',
  created_at timestamptz not null default now(),
  constraint news_articles_source_https check (source_url like 'https://%')
);

create index news_articles_published_idx
  on public.news_articles (published_at desc)
  where status = 'published';

create table public.family_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  invite_code_hash text,
  created_at timestamptz not null default now()
);

create table public.family_members (
  group_id uuid not null references public.family_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- Automatically register the creator as the group's owner.
create or replace function public.add_family_group_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.family_members (group_id, user_id, role)
  values (new.id, new.created_by, 'owner');
  return new;
end;
$$;

create trigger family_groups_add_owner
  after insert on public.family_groups
  for each row execute function public.add_family_group_owner();

create table public.family_checkins (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'ok' check (status in ('ok', 'need_help')),
  note text,
  created_at timestamptz not null default now(),
  foreign key (group_id, user_id) references public.family_members(group_id, user_id) on delete cascade
);

create index family_checkins_group_time_idx
  on public.family_checkins (group_id, created_at desc);

-- Helper avoids recursive RLS policies on family_members.
create or replace function public.is_family_member(target_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.family_members
    where group_id = target_group and user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_family_member(uuid) from public;
grant execute on function public.is_family_member(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.cities enable row level security;
alter table public.user_city_subscriptions enable row level security;
alter table public.alert_sources enable row level security;
alter table public.alert_events enable row level security;
alter table public.news_articles enable row level security;
alter table public.family_groups enable row level security;
alter table public.family_members enable row level security;
alter table public.family_checkins enable row level security;

create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "cities_read_active" on public.cities
  for select to anon, authenticated using (is_active = true);

create policy "subscriptions_select_own" on public.user_city_subscriptions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "subscriptions_insert_own" on public.user_city_subscriptions
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "subscriptions_delete_own" on public.user_city_subscriptions
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "published_alerts_read" on public.alert_events
  for select to anon, authenticated using (status = 'published');
create policy "published_news_read" on public.news_articles
  for select to anon, authenticated using (status = 'published');

create policy "family_groups_read_members" on public.family_groups
  for select to authenticated using (public.is_family_member(id));
create policy "family_groups_create_owner" on public.family_groups
  for insert to authenticated with check (created_by = (select auth.uid()));
create policy "family_groups_update_owner" on public.family_groups
  for update to authenticated using (
    exists (select 1 from public.family_members m where m.group_id = id and m.user_id = (select auth.uid()) and m.role = 'owner')
  ) with check (
    exists (select 1 from public.family_members m where m.group_id = id and m.user_id = (select auth.uid()) and m.role = 'owner')
  );

create policy "family_members_read_group" on public.family_members
  for select to authenticated using (public.is_family_member(group_id));
create policy "family_members_leave_self" on public.family_members
  for delete to authenticated using (user_id = (select auth.uid()) and role <> 'owner');

create policy "family_checkins_read_group" on public.family_checkins
  for select to authenticated using (public.is_family_member(group_id));
create policy "family_checkins_create_self" on public.family_checkins
  for insert to authenticated with check (
    user_id = (select auth.uid()) and public.is_family_member(group_id)
  );

-- Sensitive ingestion tables are server-managed only. No client write policies.
revoke insert, update, delete on public.alert_sources from anon, authenticated;
revoke insert, update, delete on public.alert_events from anon, authenticated;
revoke insert, update, delete on public.news_articles from anon, authenticated;

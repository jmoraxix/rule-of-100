-- R100-T02: profiles, challenges, daily_entries + RLS.
-- Progress writes (daily_entries) belong to T03's SQL functions; clients only read them.

create type public.unit_type as enum ('count', 'minutes');
create type public.challenge_status as enum ('active', 'completed', 'abandoned');

-- profiles ------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  timezone text not null,
  created_at timestamptz not null default now()
);

-- CHECK needs an immutable expression and the tz catalog is not, so validate in a trigger.
create function public.profiles_validate_timezone()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.timezone is not null and not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception 'invalid timezone: %', new.timezone using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger profiles_validate_timezone
  before insert or update of timezone on public.profiles
  for each row execute function public.profiles_validate_timezone();

-- challenges ----------------------------------------------------------------

create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  action text not null check (action ~ '[^[:space:]]'),
  unit_type public.unit_type not null,
  start_date date not null,
  status public.challenge_status not null default 'active',
  -- target of daily_entries' composite FK (entry owner = challenge owner)
  unique (id, user_id)
);

create index challenges_user_id_idx on public.challenges (user_id);

-- daily_entries -------------------------------------------------------------

create table public.daily_entries (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null,
  user_id uuid not null,
  entry_date date not null,
  value integer not null default 0 check (value >= 0),
  timer_started_at timestamptz,
  completed_at timestamptz,
  unique (challenge_id, entry_date),
  constraint daily_entries_challenge_owner_fkey
    foreign key (challenge_id, user_id) references public.challenges (id, user_id) on delete cascade
);

-- At most one running timer per user.
create unique index daily_entries_one_running_timer
  on public.daily_entries (user_id) where timer_started_at is not null;

-- privileges ----------------------------------------------------------------
-- Supabase's default privileges grant ALL to anon/authenticated; start from nothing.

revoke all on public.profiles, public.challenges, public.daily_entries from anon, authenticated;

grant select on public.profiles, public.challenges, public.daily_entries to authenticated;
grant insert (id, display_name, timezone) on public.profiles to authenticated;
grant update (display_name, timezone) on public.profiles to authenticated;
grant insert (user_id, action, unit_type, start_date) on public.challenges to authenticated;
grant update (action, status) on public.challenges to authenticated;
-- daily_entries: no insert/update/delete for clients (T03 functions write it). No deletes anywhere.

-- RLS -----------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.challenges enable row level security;
alter table public.daily_entries enable row level security;

create policy profiles_select_own on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy challenges_select_own on public.challenges
  for select to authenticated using (user_id = (select auth.uid()));
create policy challenges_insert_own on public.challenges
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy challenges_update_own on public.challenges
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy daily_entries_select_own on public.daily_entries
  for select to authenticated using (user_id = (select auth.uid()));

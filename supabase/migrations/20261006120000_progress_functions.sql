-- R100-T03: every progress rule as a SQL function; the client only calls RPCs and reads goal_progress.

-- Close T02 gaps -------------------------------------------------------------

-- Challenges are created/abandoned through functions (start_date from SQL, status only active→abandoned).
revoke insert on public.challenges from authenticated;
revoke update (status) on public.challenges from authenticated;
-- The timezone is set once at sign-up; changing it would move the day boundary (invariant 5).
revoke update (timezone) on public.profiles from authenticated;

alter table public.challenges
  add constraint challenges_action_length check (char_length(action) between 1 and 120);
alter table public.profiles
  add constraint profiles_display_name_length check (char_length(display_name) <= 50);

-- Drives "last touched" in landscape mode. Written only by the functions below.
alter table public.daily_entries
  add column last_activity_at timestamptz not null default now();

-- Internal helpers (not granted to any client role) ------------------------

-- The one place that turns an instant into a user's calendar day. Takes the instant so tests can
-- probe midnight and timezone edges.
create function public._local_date(p_tz text, p_ts timestamptz)
returns date
language sql
stable
set search_path = ''
as $$ select (p_ts at time zone p_tz)::date $$;

create function public._refresh_status(p_challenge uuid)
returns void
language sql
set search_path = ''
as $$
  update public.challenges set status = 'completed'
  where id = p_challenge and status = 'active'
    and (select count(*) from public.daily_entries
         where challenge_id = p_challenge and completed_at is not null) >= 100;
$$;

-- Stops a running timer at p_until: folds the elapsed seconds into value, and sets completed_at at
-- the exact instant 6000 s was crossed.
create function public._fold(p_entry uuid, p_until timestamptz)
returns public.daily_entries
language plpgsql
set search_path = ''
as $$
declare
  e public.daily_entries;
  secs integer;
begin
  select * into e from public.daily_entries
  where id = p_entry and timer_started_at is not null
  for update;
  if not found then
    return null;
  end if;
  secs := greatest(0, floor(extract(epoch from p_until - e.timer_started_at)))::integer;
  update public.daily_entries set
    value = e.value + secs,
    timer_started_at = null,
    completed_at = case
      when completed_at is null and e.value + secs >= 6000
        then e.timer_started_at + make_interval(secs => 6000 - e.value)
      else completed_at end,
    last_activity_at = p_until
  where id = p_entry
  returning * into e;
  perform public._refresh_status(e.challenge_id);
  return e;
end;
$$;

-- ponytail: stale timers stop lazily, on the user's next RPC call, capped at the local midnight
-- that ended their entry's day, so the credit is the same whenever the fold happens. Until then the
-- row still has timer_started_at set (goal_progress only looks at today's entry). Add a pg_cron
-- sweep if anything ever needs those rows settled without the user coming back.
create function public._pause_stale(p_uid uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  r record;
begin
  select e.id, ((e.entry_date + 1)::timestamp at time zone p.timezone) as midnight into r
  from public.daily_entries e
  join public.profiles p on p.id = e.user_id
  where e.user_id = p_uid
    and e.timer_started_at is not null
    and e.entry_date < public._local_date(p.timezone, now());
  if found then
    perform public._fold(r.id, r.midnight);
  end if;
end;
$$;

-- Caller, stale-timer cleanup, ownership/status/unit checks, and the caller's local today.
create function public._ctx(p_challenge uuid, p_unit public.unit_type, out uid uuid, out today date)
language plpgsql
set search_path = ''
as $$
declare
  c record;
begin
  uid := auth.uid();
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  perform public._pause_stale(uid);
  select ch.status, ch.unit_type, p.timezone into c
  from public.challenges ch
  join public.profiles p on p.id = ch.user_id
  where ch.id = p_challenge and ch.user_id = uid;
  if not found then
    raise exception 'challenge not found' using errcode = 'P0002';
  end if;
  if c.status <> 'active' then
    raise exception 'challenge is not active';
  end if;
  if c.unit_type <> p_unit then
    raise exception 'challenge is not a % goal', p_unit;
  end if;
  today := public._local_date(c.timezone, now());
end;
$$;

-- Client API ----------------------------------------------------------------

create function public.create_challenge(p_action text, p_unit public.unit_type)
returns public.challenges
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  tz text;
  ch public.challenges;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  perform public._pause_stale(uid);
  select timezone into tz from public.profiles where id = uid;
  if not found then
    raise exception 'profile required' using errcode = 'P0002';
  end if;
  insert into public.challenges (user_id, action, unit_type, start_date)
  values (uid, p_action, p_unit, public._local_date(tz, now()))
  returning * into ch;
  return ch;
end;
$$;

create function public.abandon_challenge(p_id uuid)
returns public.challenges
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  ch public.challenges;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  perform public._pause_stale(uid);
  update public.challenges set status = 'abandoned'
  where id = p_id and user_id = uid and status = 'active'
  returning * into ch;
  if not found then
    raise exception 'challenge not found or not active' using errcode = 'P0002';
  end if;
  -- Don't leave a timer running on a goal that can no longer be paused.
  perform public._fold(id, now()) from public.daily_entries
  where challenge_id = p_id and timer_started_at is not null;
  return ch;
end;
$$;

create function public.increment(p_challenge uuid)
returns public.daily_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  c record;
  e public.daily_entries;
begin
  select * into c from public._ctx(p_challenge, 'count');
  insert into public.daily_entries (challenge_id, user_id, entry_date, value)
  values (p_challenge, c.uid, c.today, 1)
  on conflict (challenge_id, entry_date)
    do update set value = public.daily_entries.value + 1, last_activity_at = now()
  returning * into e;
  if e.completed_at is null and e.value >= 100 then
    update public.daily_entries set completed_at = now() where id = e.id returning * into e;
    perform public._refresh_status(p_challenge);
  end if;
  return e;
end;
$$;

create function public.timer_start(p_challenge uuid)
returns public.daily_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  c record;
  e public.daily_entries;
begin
  select * into c from public._ctx(p_challenge, 'minutes');
  if exists (select 1 from public.daily_entries where challenge_id = p_challenge and entry_date = c.today) then
    raise exception 'timer already started today';
  end if;
  if exists (select 1 from public.daily_entries where user_id = c.uid and timer_started_at is not null) then
    raise exception 'another timer is already running';
  end if;
  insert into public.daily_entries (challenge_id, user_id, entry_date, timer_started_at)
  values (p_challenge, c.uid, c.today, now())
  returning * into e;
  return e;
end;
$$;

create function public.timer_pause(p_challenge uuid)
returns public.daily_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  c record;
  e public.daily_entries;
begin
  select * into c from public._ctx(p_challenge, 'minutes');
  select * into e from public.daily_entries where challenge_id = p_challenge and entry_date = c.today;
  if not found or e.timer_started_at is null then
    raise exception 'timer is not running';
  end if;
  return public._fold(e.id, now());
end;
$$;

create function public.timer_resume(p_challenge uuid)
returns public.daily_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  c record;
  e public.daily_entries;
begin
  select * into c from public._ctx(p_challenge, 'minutes');
  select * into e from public.daily_entries
  where challenge_id = p_challenge and entry_date = c.today
  for update;
  if not found then
    raise exception 'timer not started today';
  end if;
  if e.timer_started_at is not null then
    raise exception 'timer is already running';
  end if;
  if exists (select 1 from public.daily_entries where user_id = c.uid and timer_started_at is not null) then
    raise exception 'another timer is already running';
  end if;
  update public.daily_entries set timer_started_at = now(), last_activity_at = now()
  where id = e.id
  returning * into e;
  return e;
end;
$$;

-- Read model ----------------------------------------------------------------

create view public.goal_progress with (security_invoker = true) as
select
  c.id,
  c.action,
  c.unit_type,
  c.status,
  c.start_date,
  s.completed_days,
  least(100, s.completed_days + case when t.completed_at is null then 1 else 0 end) as day_number,
  k.streak,
  coalesce(t.value, 0) + coalesce(floor(extract(epoch from now() - t.timer_started_at))::integer, 0) as today_value,
  t.completed_at is not null as today_completed,
  t.timer_started_at is not null as timer_running,
  t.timer_started_at,
  s.last_activity_at
from public.challenges c
join public.profiles p on p.id = c.user_id
-- Same expression as _local_date, inlined: the helper isn't executable by the invoking client.
cross join lateral (select (now() at time zone p.timezone)::date as today) d
left join public.daily_entries t on t.challenge_id = c.id and t.entry_date = d.today
-- Streak ends today when today is complete, else yesterday.
cross join lateral (select d.today - case when t.completed_at is null then 1 else 0 end as streak_end) a
cross join lateral (
  select count(*) filter (where e.completed_at is not null)::integer as completed_days,
         max(e.last_activity_at) as last_activity_at
  from public.daily_entries e
  where e.challenge_id = c.id
) s
cross join lateral (
  select count(*)::integer as streak
  from (
    select e.entry_date, row_number() over (order by e.entry_date desc)::integer as rn
    from public.daily_entries e
    where e.challenge_id = c.id and e.completed_at is not null and e.entry_date <= a.streak_end
  ) x
  where x.entry_date = a.streak_end - (x.rn - 1)
) k;

-- Privileges ----------------------------------------------------------------
-- Supabase's default privileges grant EXECUTE / ALL to anon and authenticated; start from nothing.

revoke execute on function
  public._local_date(text, timestamptz),
  public._refresh_status(uuid),
  public._fold(uuid, timestamptz),
  public._pause_stale(uuid),
  public._ctx(uuid, public.unit_type)
from public, anon, authenticated;

revoke execute on function
  public.create_challenge(text, public.unit_type),
  public.abandon_challenge(uuid),
  public.increment(uuid),
  public.timer_start(uuid),
  public.timer_pause(uuid),
  public.timer_resume(uuid)
from public, anon;
grant execute on function
  public.create_challenge(text, public.unit_type),
  public.abandon_challenge(uuid),
  public.increment(uuid),
  public.timer_start(uuid),
  public.timer_pause(uuid),
  public.timer_resume(uuid)
to authenticated;

revoke all on public.goal_progress from anon, authenticated;
grant select on public.goal_progress to authenticated;

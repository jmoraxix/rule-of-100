-- R100-T11: a running timer stops by itself at 6000 s (the "0" of the countdown) unless the user
-- chose overtime. Enforced on the server, so it holds with the app closed.

-- Set only by timer_resume (clients have no UPDATE on daily_entries).
alter table public.daily_entries add column overtime boolean not null default false;

-- Entries already past 6000 before this migration keep counting as before.
update public.daily_entries e set overtime = true
from public.challenges c
where c.id = e.challenge_id and c.unit_type = 'minutes'
  and e.value + coalesce(floor(extract(epoch from now() - e.timer_started_at))::integer, 0) > 6000;

-- Same as T03, plus the cap: without overtime the fold never credits past 6000.
create or replace function public._fold(p_entry uuid, p_until timestamptz)
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
  if not e.overtime then
    secs := least(secs, greatest(0, 6000 - e.value));
  end if;
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

-- Lazy stop, run first by every RPC (via _ctx, create_challenge, abandon_challenge): a timer from a
-- past day stops at its local midnight (T03), and a non-overtime timer that reached 6000 stops at
-- the crossing instant, whichever comes first. Same deterministic credit whenever it runs.
create or replace function public._pause_stale(p_uid uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  r record;
begin
  select e.id,
         least(
           case when e.entry_date < public._local_date(p.timezone, now())
             then (e.entry_date + 1)::timestamp at time zone p.timezone end,
           case when not e.overtime
             then e.timer_started_at + make_interval(secs => greatest(0, 6000 - e.value)) end
         ) as until
    into r
  from public.daily_entries e
  join public.profiles p on p.id = e.user_id
  where e.user_id = p_uid
    and e.timer_started_at is not null
    and (e.entry_date < public._local_date(p.timezone, now())
         or (not e.overtime and now() >= e.timer_started_at + make_interval(secs => greatest(0, 6000 - e.value))))
  for update of e;
  if found then
    perform public._fold(r.id, r.until);
  end if;
end;
$$;

-- Same as T03 plus FOR UPDATE on the entry (security MINOR F01, #8).
create or replace function public.timer_pause(p_challenge uuid)
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
  select * into e from public.daily_entries where challenge_id = p_challenge and entry_date = c.today
  for update;
  if not found or e.timer_started_at is null then
    raise exception 'timer is not running';
  end if;
  return public._fold(e.id, now());
end;
$$;

-- Same as T03; resuming once today's value reached 6000 is "Start overtime": it runs uncapped.
-- (timer_start always begins at 0, so it never enables overtime.)
create or replace function public.timer_resume(p_challenge uuid)
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
  update public.daily_entries set
    timer_started_at = now(),
    last_activity_at = now(),
    overtime = overtime or value >= 6000
  where id = e.id
  returning * into e;
  return e;
end;
$$;

-- Same as T03, with today_value capped live at 6000 outside overtime, plus overtime/timer_capped.
create or replace view public.goal_progress with (security_invoker = true) as
select
  c.id,
  c.action,
  c.unit_type,
  c.status,
  c.start_date,
  s.completed_days,
  least(100, s.completed_days + case when t.completed_at is null then 1 else 0 end) as day_number,
  k.streak,
  case when c.unit_type = 'minutes' and not coalesce(t.overtime, false)
    then least(6000, r.raw_value) else r.raw_value end as today_value,
  t.completed_at is not null as today_completed,
  t.timer_started_at is not null as timer_running,
  t.timer_started_at,
  s.last_activity_at,
  coalesce(t.overtime, false) as overtime,
  -- Reached 6000 while running and not yet folded by an RPC: show it as stopped.
  coalesce(t.timer_started_at is not null and not t.overtime and r.raw_value >= 6000, false) as timer_capped
from public.challenges c
join public.profiles p on p.id = c.user_id
-- Same expression as _local_date, inlined: the helper isn't executable by the invoking client.
cross join lateral (select (now() at time zone p.timezone)::date as today) d
left join public.daily_entries t on t.challenge_id = c.id and t.entry_date = d.today
cross join lateral (
  select coalesce(t.value, 0) + coalesce(floor(extract(epoch from now() - t.timer_started_at))::integer, 0) as raw_value
) r
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

-- Privileges (replace keeps the T03 ACLs; restated so this file stands on its own) ----------

revoke execute on function public._fold(uuid, timestamptz), public._pause_stale(uuid)
from public, anon, authenticated;
revoke execute on function public.timer_pause(uuid), public.timer_resume(uuid) from public, anon;
grant execute on function public.timer_pause(uuid), public.timer_resume(uuid) to authenticated;

revoke all on public.goal_progress from anon, authenticated;
grant select on public.goal_progress to authenticated;

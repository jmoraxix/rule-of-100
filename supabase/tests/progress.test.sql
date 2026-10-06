begin;
select plan(58);

-- A lives in Costa Rica (UTC-6, no DST), B in UTC. C has no profile.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local'),
  ('00000000-0000-0000-0000-00000000000c', 'c@test.local');
insert into public.profiles (id, timezone) values
  ('00000000-0000-0000-0000-00000000000a', 'America/Costa_Rica'),
  ('00000000-0000-0000-0000-00000000000b', 'UTC');
insert into public.challenges (id, user_id, action, unit_type, start_date) values
  ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000a', 'Push-ups', 'count', '2026-01-01'),
  ('10000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000000a', 'Content', 'minutes', '2026-01-01'),
  ('10000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-00000000000a', 'Reading', 'minutes', '2026-01-01'),
  ('10000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-00000000000a', 'Calls', 'count', '2026-01-01'),
  ('10000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-00000000000a', 'Drawing', 'minutes', '2026-01-01'),
  ('10000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-00000000000a', 'Writing', 'count', '2026-01-01'),
  ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000b', 'Squats', 'count', '2026-01-01');

-- Local date --------------------------------------------------------------------
select is(public._local_date('America/Costa_Rica', '2026-10-06 05:30:00+00'), '2026-10-05'::date,
  '23:30 in Costa Rica is still the 5th while UTC is the 6th');
select is(public._local_date('UTC', '2026-10-06 05:30:00+00'), '2026-10-06'::date, 'same instant in UTC is the 6th');
select is(public._local_date('America/Costa_Rica', '2026-10-06 05:59:59+00'), '2026-10-05'::date,
  'one second before Costa Rica midnight');
select is(public._local_date('America/Costa_Rica', '2026-10-06 06:00:00+00'), '2026-10-06'::date,
  'Costa Rica midnight starts the 6th');

-- Stale timer: A's "Drawing" timer still running from 10 minutes before last local midnight, in
-- overtime so only the midnight cap applies (without overtime it would stop at 6000 first).
insert into public.daily_entries (challenge_id, user_id, entry_date, value, overtime, timer_started_at) values
  ('10000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-00000000000a',
   public._local_date('America/Costa_Rica', now()) - 1, 5900, true,
   (public._local_date('America/Costa_Rica', now())::timestamp at time zone 'America/Costa_Rica') - interval '600 seconds');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;

select is((select (public.increment('10000000-0000-0000-0000-0000000000a1')).value), 1, 'first increment creates the entry at 1');

reset role;
select is((select value from public.daily_entries where challenge_id = '10000000-0000-0000-0000-0000000000a5'), 6500,
  'stale timer is auto-paused and capped at local midnight');
select is((select timer_started_at from public.daily_entries where challenge_id = '10000000-0000-0000-0000-0000000000a5'), null,
  'stale timer is cleared');
select is((select completed_at from public.daily_entries where challenge_id = '10000000-0000-0000-0000-0000000000a5'),
  (public._local_date('America/Costa_Rica', now())::timestamp at time zone 'America/Costa_Rica') - interval '500 seconds',
  'stale crossing sets completed_at at started_at + (6000 - old value) s, on its own day');

-- Counter ----------------------------------------------------------------------
set local role authenticated;
select is((select (public.increment('10000000-0000-0000-0000-0000000000a1')).value), 2, 'increment adds exactly 1');
select is((select entry_date from public.daily_entries where challenge_id = '10000000-0000-0000-0000-0000000000a1'),
  (now() at time zone 'America/Costa_Rica')::date, 'entry_date is the user''s local today');
select throws_ok($$update public.daily_entries set value = 0$$, '42501', null, 'client cannot set or lower a value');
select is(
  (select string_agg(p.proname::text, ',' order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prorettype <> 'trigger'::regtype
      and has_function_privilege('authenticated', p.oid, 'execute')),
  'abandon_challenge,create_challenge,increment,timer_pause,timer_resume,timer_start',
  'the only client RPCs are these six (no decrement, no set-value)');
select throws_ok($$select public.increment('10000000-0000-0000-0000-0000000000a2')$$, 'P0001',
  'challenge is not a count goal', 'increment refuses a minutes goal');
select throws_ok($$select public._local_date('UTC', now())$$, '42501', null, 'helpers are not executable by clients');

reset role;
update public.daily_entries set value = 98 where challenge_id = '10000000-0000-0000-0000-0000000000a1';
set local role authenticated;
select is((select (public.increment('10000000-0000-0000-0000-0000000000a1')).completed_at), null, 'no completed_at at 99');
select is((select (public.increment('10000000-0000-0000-0000-0000000000a1')).completed_at), now(), 'completed_at set at 100');
reset role;
update public.daily_entries set completed_at = '2026-01-01 00:00:00+00' where challenge_id = '10000000-0000-0000-0000-0000000000a1';
set local role authenticated;
select is((select (public.increment('10000000-0000-0000-0000-0000000000a1')).completed_at), '2026-01-01 00:00:00+00'::timestamptz,
  'completed_at never moves once set');
select is((select today_value from public.goal_progress where id = '10000000-0000-0000-0000-0000000000a1'), 101,
  'above 100 is allowed');

-- Timer ------------------------------------------------------------------------
select is((select (public.timer_start('10000000-0000-0000-0000-0000000000a2')).timer_started_at), now(), 'timer_start sets timer_started_at');
select throws_ok($$select public.timer_start('10000000-0000-0000-0000-0000000000a3')$$, 'P0001',
  'another timer is already running', 'second running timer refused');
select throws_ok($$select public.timer_resume('10000000-0000-0000-0000-0000000000a2')$$, 'P0001',
  'timer is already running', 'resume refused while running');
select throws_ok($$select public.increment('10000000-0000-0000-0000-0000000000a2')$$, 'P0001',
  'challenge is not a count goal', 'timer goal cannot be incremented');

reset role;
update public.daily_entries set timer_started_at = now() - interval '90 seconds' where challenge_id = '10000000-0000-0000-0000-0000000000a2';
set local role authenticated;
select is((select today_value from public.goal_progress where id = '10000000-0000-0000-0000-0000000000a2'), 90,
  'goal_progress today_value includes running seconds');
select is((select (public.timer_pause('10000000-0000-0000-0000-0000000000a2')).value), 90, 'pause folds elapsed seconds into value');
select is((select timer_running from public.goal_progress where id = '10000000-0000-0000-0000-0000000000a2'), false, 'pause clears the timer');
select throws_ok($$select public.timer_start('10000000-0000-0000-0000-0000000000a2')$$, 'P0001',
  'timer already started today', 'start refused twice in a day');
select throws_ok($$select public.timer_pause('10000000-0000-0000-0000-0000000000a2')$$, 'P0001',
  'timer is not running', 'pause refused when paused');
select throws_ok($$select public.timer_resume('10000000-0000-0000-0000-0000000000a5')$$, 'P0001',
  'timer not started today', 'resume only works on today''s entry');
select lives_ok($$select public.timer_resume('10000000-0000-0000-0000-0000000000a2')$$, 'resume after pause');
select is((select overtime from public.goal_progress where id = '10000000-0000-0000-0000-0000000000a2'), false,
  'resume before 6000 does not enable overtime');
select throws_ok($$update public.daily_entries set overtime = true$$, '42501', null, 'client cannot set overtime');

reset role;
update public.daily_entries set timer_started_at = now() - interval '5950 seconds' where challenge_id = '10000000-0000-0000-0000-0000000000a2';
set local role authenticated;
-- 90 + 5950 = 6040 running, no overtime: stops at 6000 by itself.
select results_eq(
  $$select today_value, timer_capped, overtime from public.goal_progress where id = '10000000-0000-0000-0000-0000000000a2'$$,
  $$values (6000, true, false)$$, 'goal_progress caps live at 6000 and flags the timer as capped');
select lives_ok($$select public.increment('10000000-0000-0000-0000-0000000000a1')$$, 'any RPC finalizes a capped timer');
select results_eq(
  $$select value, completed_at, timer_started_at from public.daily_entries where challenge_id = '10000000-0000-0000-0000-0000000000a2'$$,
  $$values (6000, now() - interval '40 seconds', null::timestamptz)$$,
  'capped timer credited exactly 6000, completed_at at the 6000 s crossing, stopped');
select lives_ok($$select public.timer_resume('10000000-0000-0000-0000-0000000000a2')$$, 'Start overtime after 6000');
select is((select overtime from public.goal_progress where id = '10000000-0000-0000-0000-0000000000a2'), true,
  'resume at 6000 enables overtime');
reset role;
update public.daily_entries set timer_started_at = now() - interval '100 seconds' where challenge_id = '10000000-0000-0000-0000-0000000000a2';
set local role authenticated;
select results_eq(
  $$select today_value, timer_capped from public.goal_progress where id = '10000000-0000-0000-0000-0000000000a2'$$,
  $$values (6100, false)$$, 'overtime counts past 6000 live');
select is((select (public.timer_pause('10000000-0000-0000-0000-0000000000a2')).value), 6100, 'overtime pause credits past 6000');
select is((select completed_at from public.daily_entries where challenge_id = '10000000-0000-0000-0000-0000000000a2'),
  now() - interval '40 seconds', 'completed_at does not move in overtime');

-- 100th completed day completes the challenge; missed days don't end it -----------
reset role;
insert into public.daily_entries (challenge_id, user_id, entry_date, value, completed_at)
select '10000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-00000000000a',
       public._local_date('America/Costa_Rica', now()) - g, 100, now()
from generate_series(1, 99) g;
insert into public.daily_entries (challenge_id, user_id, entry_date, value) values
  ('10000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-00000000000a', public._local_date('America/Costa_Rica', now()), 99);
-- "Writing": completed yesterday and the day before, a gap, then one more; today in progress.
insert into public.daily_entries (challenge_id, user_id, entry_date, value, completed_at)
select '10000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-00000000000a',
       public._local_date('America/Costa_Rica', now()) - g, 100, now()
from unnest(array[1, 2, 4]) g;
insert into public.daily_entries (challenge_id, user_id, entry_date, value) values
  ('10000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-00000000000a', public._local_date('America/Costa_Rica', now()), 5);
set local role authenticated;

select results_eq(
  $$select completed_days, day_number, streak, today_completed from public.goal_progress where id = '10000000-0000-0000-0000-0000000000a6'$$,
  $$values (3, 4, 2, false)$$, 'streak ends yesterday while today is incomplete; gaps reset it but not completed_days');
select results_eq(
  $$select completed_days, day_number, streak from public.goal_progress where id = '10000000-0000-0000-0000-0000000000a1'$$,
  $$values (1, 1, 1)$$, 'today complete: day_number stays, streak counts today');
select lives_ok($$select public.increment('10000000-0000-0000-0000-0000000000a4')$$, '100th day reaches 100');
select results_eq(
  $$select status::text, completed_days, day_number, streak from public.goal_progress where id = '10000000-0000-0000-0000-0000000000a4'$$,
  $$values ('completed', 100, 100, 100)$$, '100th completed day completes the challenge');
select throws_ok($$select public.increment('10000000-0000-0000-0000-0000000000a4')$$, 'P0001',
  'challenge is not active', 'a completed challenge takes no more progress');

-- create / abandon --------------------------------------------------------------
select is((select (public.create_challenge('Stretching', 'count')).start_date), (now() at time zone 'America/Costa_Rica')::date,
  'create_challenge derives start_date from the profile timezone');
select throws_ok($$select public.create_challenge(repeat('x', 121), 'count')$$, '23514', null, 'action over 120 chars refused');
select lives_ok($$select public.timer_start('10000000-0000-0000-0000-0000000000a3')$$, 'start the second timer once the first is paused');
select is((select (public.abandon_challenge('10000000-0000-0000-0000-0000000000a3')).status::text), 'abandoned', 'abandon an active goal');
select is((select timer_running from public.goal_progress where id = '10000000-0000-0000-0000-0000000000a3'), false,
  'abandoning stops its timer');
select throws_ok($$select public.abandon_challenge('10000000-0000-0000-0000-0000000000a3')$$, 'P0002',
  'challenge not found or not active', 'abandoned cannot be abandoned or reactivated');

-- B cannot act on A's challenges ------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select throws_ok($$select public.increment('10000000-0000-0000-0000-0000000000a1')$$, 'P0002', 'challenge not found', 'B cannot increment A''s goal');
select throws_ok($$select public.timer_resume('10000000-0000-0000-0000-0000000000a2')$$, 'P0002', 'challenge not found', 'B cannot resume A''s timer');
select throws_ok($$select public.abandon_challenge('10000000-0000-0000-0000-0000000000a1')$$, 'P0002',
  'challenge not found or not active', 'B cannot abandon A''s goal');
select is((select count(*) from public.goal_progress), 1::bigint, 'B sees only its own goal in goal_progress');

-- No profile, no challenge
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select throws_ok($$select public.create_challenge('x', 'count')$$, 'P0002', 'profile required', 'create_challenge requires a profile');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select throws_ok($$update public.profiles set display_name = repeat('x', 51)$$, '23514', null, 'display_name over 50 chars refused');

-- anon --------------------------------------------------------------------------
reset role;
set local role anon;
select throws_ok(
  $$select public.increment('10000000-0000-0000-0000-0000000000b1')$$,
  '42501', null, 'anon cannot execute increment');
select is(
  (select count(*)::int from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prorettype <> 'trigger'::regtype
     and has_function_privilege('anon', p.oid, 'execute')),
  0, 'anon can execute no function in public');

select * from finish();
rollback;

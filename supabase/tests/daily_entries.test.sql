begin;
select plan(19);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');
insert into public.profiles (id, timezone) values
  ('00000000-0000-0000-0000-00000000000a', 'UTC'),
  ('00000000-0000-0000-0000-00000000000b', 'UTC');
insert into public.challenges (id, user_id, action, unit_type, start_date) values
  ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000a', 'Content', 'minutes', '2026-10-01'),
  ('10000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000000a', 'Reading', 'minutes', '2026-10-01'),
  ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000b', 'Calls', 'minutes', '2026-10-01');
insert into public.daily_entries (id, challenge_id, user_id, entry_date) values
  ('20000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000a', '2026-10-01'),
  ('20000000-0000-0000-0000-0000000000a2', '10000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000000a', '2026-10-01'),
  ('20000000-0000-0000-0000-0000000000b1', '10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000b', '2026-10-01');

-- Constraints
select is((select value from public.daily_entries where id = '20000000-0000-0000-0000-0000000000a1'), 0,
  'value defaults to 0');
select throws_ok(
  $$insert into public.daily_entries (challenge_id, user_id, entry_date) values ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000a', '2026-10-01')$$,
  '23505', null, 'one entry per (challenge_id, entry_date)');
select throws_ok(
  $$insert into public.daily_entries (challenge_id, user_id, entry_date, value) values ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000a', '2026-10-02', -1)$$,
  '23514', null, 'value cannot be negative');
select throws_ok(
  $$insert into public.daily_entries (challenge_id, user_id, entry_date, value) values ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000a', '2026-10-02', null)$$,
  '23502', null, 'value is NOT NULL');
select throws_ok(
  $$insert into public.daily_entries (challenge_id, user_id, entry_date) values ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000b', '2026-10-02')$$,
  '23503', null, 'entry user_id must equal the challenge owner');

-- One running timer per user
select lives_ok(
  $$update public.daily_entries set timer_started_at = now() where id = '20000000-0000-0000-0000-0000000000a1'$$,
  'A starts a timer');
select throws_ok(
  $$update public.daily_entries set timer_started_at = now() where id = '20000000-0000-0000-0000-0000000000a2'$$,
  '23505', null, 'A cannot run a second timer on another goal');
select lives_ok(
  $$update public.daily_entries set timer_started_at = now() where id = '20000000-0000-0000-0000-0000000000b1'$$,
  'B can run a timer while A''s runs');
select lives_ok(
  $$insert into public.daily_entries (challenge_id, user_id, entry_date) values ('10000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000000a', '2026-10-02')$$,
  'stopped entries are unconstrained by the running-timer index');

-- As user B
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);

select is((select count(*) from public.daily_entries), 1::bigint, 'B sees only its own entry');
select is((select count(*) from public.daily_entries where user_id = '00000000-0000-0000-0000-00000000000a'), 0::bigint,
  'B sees 0 of A''s entries');
select throws_ok(
  $$insert into public.daily_entries (challenge_id, user_id, entry_date) values ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000b', '2026-10-03')$$,
  '42501', null, 'authenticated cannot insert entries, even its own');
select throws_ok(
  $$insert into public.daily_entries (challenge_id, user_id, entry_date) values ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000a', '2026-10-03')$$,
  '42501', null, 'B cannot insert entries as A');
select throws_ok(
  $$update public.daily_entries set value = 100 where id = '20000000-0000-0000-0000-0000000000b1'$$,
  '42501', null, 'authenticated cannot update its own entry');
select throws_ok(
  $$update public.daily_entries set value = 0 where id = '20000000-0000-0000-0000-0000000000a1'$$,
  '42501', null, 'B cannot update A''s entry');
select throws_ok(
  $$delete from public.daily_entries where id = '20000000-0000-0000-0000-0000000000b1'$$,
  '42501', null, 'authenticated cannot delete entries');

-- As anon
reset role;
set local role anon;
select throws_ok($$select * from public.daily_entries$$, '42501', null, 'anon cannot select entries');
select throws_ok(
  $$update public.daily_entries set value = 100$$,
  '42501', null, 'anon cannot update entries');

reset role;
select is((select sum(value) from public.daily_entries), 0::bigint, 'no entry values changed');

select * from finish();
rollback;

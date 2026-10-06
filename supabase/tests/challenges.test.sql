begin;
select plan(18);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');
insert into public.profiles (id, timezone) values
  ('00000000-0000-0000-0000-00000000000a', 'UTC'),
  ('00000000-0000-0000-0000-00000000000b', 'UTC');
insert into public.challenges (id, user_id, action, unit_type, start_date) values
  ('10000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', 'Outreach', 'count', '2026-10-01');

-- Constraints
select is((select status from public.challenges where id = '10000000-0000-0000-0000-00000000000a'),
  'active'::public.challenge_status, 'status defaults to active');
select throws_ok(
  $$insert into public.challenges (user_id, action, unit_type, start_date) values ('00000000-0000-0000-0000-00000000000a', null, 'count', '2026-10-01')$$,
  '23502', null, 'action is NOT NULL');
select throws_ok(
  $$insert into public.challenges (user_id, action, unit_type, start_date) values ('00000000-0000-0000-0000-00000000000a', '', 'count', '2026-10-01')$$,
  '23514', null, 'empty action refused');
select throws_ok(
  $$insert into public.challenges (user_id, action, unit_type, start_date) values ('00000000-0000-0000-0000-00000000000a', E' \t\n ', 'count', '2026-10-01')$$,
  '23514', null, 'whitespace-only action refused');
select throws_ok(
  $$insert into public.challenges (user_id, action, unit_type, start_date) values ('00000000-0000-0000-0000-00000000000a', 'x', 'hours', '2026-10-01')$$,
  '22P02', null, 'unit_type must be count or minutes');
select throws_ok(
  $$insert into public.challenges (user_id, action, unit_type, start_date) values ('00000000-0000-0000-0000-0000000000ff', 'x', 'count', '2026-10-01')$$,
  '23503', null, 'user_id must reference a profile');
select lives_ok(
  $$insert into public.challenges (user_id, action, unit_type, start_date) values ('00000000-0000-0000-0000-00000000000a', 'Content', 'minutes', '2026-10-01')$$,
  'a second active challenge for the same user is allowed');

-- As user B
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);

select is((select count(*) from public.challenges), 0::bigint, 'B sees 0 of A''s challenges');
select throws_ok(
  $$insert into public.challenges (user_id, action, unit_type, start_date) values ('00000000-0000-0000-0000-00000000000a', 'x', 'count', '2026-10-01')$$,
  '42501', null, 'B cannot insert a challenge as A');
select is_empty(
  $$update public.challenges set status = 'abandoned' where id = '10000000-0000-0000-0000-00000000000a' returning id$$,
  'B cannot update A''s challenge');
select lives_ok(
  $$insert into public.challenges (user_id, action, unit_type, start_date) values ('00000000-0000-0000-0000-00000000000b', 'Push-ups', 'count', '2026-10-01')$$,
  'B can insert its own challenge');
select throws_ok(
  $$insert into public.challenges (id, user_id, action, unit_type, start_date) values ('10000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-00000000000b', 'x', 'count', '2026-10-01')$$,
  '42501', null, 'B cannot choose the challenge id');
select is((select count(*) from public.challenges), 1::bigint, 'B sees its own challenge');
select lives_ok(
  $$update public.challenges set action = 'Pull-ups', status = 'abandoned' where user_id = '00000000-0000-0000-0000-00000000000b'$$,
  'B can update its own challenge');
select throws_ok(
  $$update public.challenges set user_id = '00000000-0000-0000-0000-00000000000a' where user_id = '00000000-0000-0000-0000-00000000000b'$$,
  '42501', null, 'B cannot change user_id');
select throws_ok(
  $$delete from public.challenges where user_id = '00000000-0000-0000-0000-00000000000b'$$,
  '42501', null, 'no DELETE grant on challenges');

-- As anon
reset role;
set local role anon;
select throws_ok($$select * from public.challenges$$, '42501', null, 'anon cannot select challenges');

reset role;
select is((select status from public.challenges where id = '10000000-0000-0000-0000-00000000000a'),
  'active'::public.challenge_status, 'A''s challenge untouched by B');

select * from finish();
rollback;

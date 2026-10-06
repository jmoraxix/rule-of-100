begin;
select plan(18);

-- Fixtures (as postgres): users A, B, C; profiles for A and B.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local'),
  ('00000000-0000-0000-0000-00000000000c', 'c@test.local'),
  ('00000000-0000-0000-0000-00000000000d', 'd@test.local');

-- Timezone validation
select lives_ok(
  $$insert into public.profiles (id, timezone) values ('00000000-0000-0000-0000-00000000000a', 'America/Costa_Rica')$$,
  'valid IANA timezone accepted');
select throws_ok(
  $$insert into public.profiles (id, timezone) values ('00000000-0000-0000-0000-00000000000b', 'Mars/Olympus_Mons')$$,
  '22023', null, 'invalid timezone refused on insert');
select throws_ok(
  $$insert into public.profiles (id, timezone) values ('00000000-0000-0000-0000-00000000000b', null)$$,
  '23502', null, 'timezone is NOT NULL');
select throws_ok(
  $$update public.profiles set timezone = 'Not/AZone' where id = '00000000-0000-0000-0000-00000000000a'$$,
  '22023', null, 'invalid timezone refused on update');
select throws_ok(
  $$insert into public.profiles (id, timezone) values ('00000000-0000-0000-0000-0000000000ff', 'UTC')$$,
  '23503', null, 'profile id must exist in auth.users');

insert into public.profiles (id, timezone) values ('00000000-0000-0000-0000-00000000000b', 'Europe/Madrid');

-- Cascade delete from auth.users
insert into public.profiles (id, timezone) values ('00000000-0000-0000-0000-00000000000d', 'UTC');
delete from auth.users where id = '00000000-0000-0000-0000-00000000000d';
select is((select count(*) from public.profiles where id = '00000000-0000-0000-0000-00000000000d'), 0::bigint,
  'deleting the auth user deletes the profile');

-- As user B
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);

select is((select count(*) from public.profiles), 1::bigint, 'B sees only its own profile');
select is((select count(*) from public.profiles where id = '00000000-0000-0000-0000-00000000000a'), 0::bigint,
  'B sees 0 of A''s profile rows');
select throws_ok(
  $$insert into public.profiles (id, timezone) values ('00000000-0000-0000-0000-00000000000c', 'UTC')$$,
  '42501', null, 'B cannot insert a profile for another user');
select is_empty(
  $$update public.profiles set display_name = 'hacked' where id = '00000000-0000-0000-0000-00000000000a' returning id$$,
  'B cannot update A''s profile');
select lives_ok(
  $$update public.profiles set display_name = 'Bee' where id = '00000000-0000-0000-0000-00000000000b'$$,
  'B can update its own display_name');
select throws_ok(
  $$update public.profiles set timezone = 'Asia/Tokyo' where id = '00000000-0000-0000-0000-00000000000b'$$,
  '42501', null, 'timezone cannot be updated after insert');
select throws_ok(
  $$update public.profiles set id = '00000000-0000-0000-0000-00000000000c' where id = '00000000-0000-0000-0000-00000000000b'$$,
  '42501', null, 'B cannot change its profile id');
select throws_ok(
  $$delete from public.profiles where id = '00000000-0000-0000-0000-00000000000b'$$,
  '42501', null, 'no DELETE grant on profiles');

-- As user C (no profile yet): own insert works
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select lives_ok(
  $$insert into public.profiles (id, timezone) values ('00000000-0000-0000-0000-00000000000c', 'UTC')$$,
  'C can insert its own profile');

-- As anon
reset role;
set local role anon;
select throws_ok($$select * from public.profiles$$, '42501', null, 'anon cannot select profiles');
select throws_ok(
  $$insert into public.profiles (id, timezone) values ('00000000-0000-0000-0000-00000000000c', 'UTC')$$,
  '42501', null, 'anon cannot insert profiles');

reset role;
select is((select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000a'), null,
  'A''s profile untouched by B');

select * from finish();
rollback;

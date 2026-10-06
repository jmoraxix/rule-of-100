begin;
select plan(1);

select has_schema('public');

select * from finish();
rollback;

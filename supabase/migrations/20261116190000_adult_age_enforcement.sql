-- Enforce The Match's adults-only policy at the database write boundary.
-- Existing incomplete rows are not rewritten; discovery already excludes ages
-- below 18. This trigger prevents new or changed profile ages under 18.

begin;

create or replace function private.enforce_match_adult_age()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.age is not null and new.age < 18 then
    raise exception 'The Match is for adults aged 18 and above'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

revoke all on function private.enforce_match_adult_age() from public, anon, authenticated;

drop trigger if exists enforce_match_adult_age on public.profiles;
create trigger enforce_match_adult_age
  before insert or update of age on public.profiles
  for each row execute function private.enforce_match_adult_age();

comment on function private.enforce_match_adult_age() is
  'Rejects profile writes that set an age below 18. Existing legacy rows are not rewritten; discovery separately excludes under-18 accounts.';

commit;

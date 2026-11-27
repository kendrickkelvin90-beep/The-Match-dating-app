-- Restore the advertiser-only to Match-member profile boundary.
-- Existing Match members can still enroll as advertisers because their profiles
-- predate enrollment. Advertiser-only accounts cannot gain member access by
-- inserting a public.profiles row. The shared auth.users row lock serializes
-- profile creation against trusted advertiser enrollment.

begin;

create or replace function private.prevent_advertiser_member_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform 1 from auth.users u where u.id = new.id for update;

  if exists (
    select 1 from private.advertiser_auth_registry r
    where r.user_id = new.id
  ) then
    raise exception 'Advertiser accounts cannot create Match member profiles'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

revoke all on function private.prevent_advertiser_member_profile()
  from public, anon, authenticated, service_role;

drop trigger if exists prevent_advertiser_member_profile on public.profiles;
create trigger prevent_advertiser_member_profile
before insert on public.profiles
for each row execute function private.prevent_advertiser_member_profile();

commit;

-- A member's private dating community is a one-time account decision.
-- Allow the first explicit selection, but prevent ordinary authenticated
-- profile updates from changing or clearing a saved choice.
create or replace function public.prevent_saved_dating_community_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  old_community text;
  new_community text;
begin
  if auth.role() = 'service_role' then
    return new;
  end if;

  old_community := nullif(pg_catalog.lower(pg_catalog.btrim(coalesce(old.answers ->> 'dating_community', ''))), '');
  new_community := nullif(pg_catalog.lower(pg_catalog.btrim(coalesce(new.answers ->> 'dating_community', ''))), '');

  if old_community in ('lgbtq', 'straight')
     and new_community is distinct from old_community then
    raise exception 'Your private dating community is already saved and cannot be changed from profile editing.'
      using errcode = '42501';
  end if;

  if new_community is not null and new_community not in ('lgbtq', 'straight') then
    raise exception 'Choose a valid private dating community.'
      using errcode = '22023';
  end if;

  return new;
end;
$function$;

drop trigger if exists prevent_saved_dating_community_change on public.member_onboarding;
create trigger prevent_saved_dating_community_change
before update of answers on public.member_onboarding
for each row
execute function public.prevent_saved_dating_community_change();

revoke all on function public.prevent_saved_dating_community_change() from public;
revoke all on function public.prevent_saved_dating_community_change() from anon, authenticated;
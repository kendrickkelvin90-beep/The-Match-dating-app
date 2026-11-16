-- General dating audience: role preferences are optional.
-- Existing members' stored sexual_roles values are preserved unchanged.

begin;

create or replace function public.is_match_profile_complete(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = target_user_id
      and p.age between 18 and 120
      and nullif(btrim(coalesce(p.display_name, '')), '') is not null
      and lower(btrim(coalesce(p.display_name, ''))) not in ('not listed', 'unknown', 'member')
      and nullif(btrim(coalesce(p.gender_identity, '')), '') is not null
      and lower(btrim(coalesce(p.gender_identity, ''))) <> 'not listed'
      and nullif(btrim(coalesce(p.interested_in, '')), '') is not null
      and lower(btrim(coalesce(p.interested_in, ''))) <> 'not listed'
      and nullif(btrim(coalesce(p.city, '')), '') is not null
      and lower(btrim(coalesce(p.city, ''))) <> 'not listed'
      and nullif(btrim(coalesce(p.bio, '')), '') is not null
      and lower(btrim(coalesce(p.bio, ''))) not in ('not listed', 'no description added yet.')
      and exists (
        select 1
        from public.profile_photos ph
        where ph.user_id = p.id
          and ph.position = 0
      )
  );
$function$;

comment on function public.is_match_profile_complete(uuid) is
  'Checks required dating profile fields and a primary photo. Sexual role preferences are optional and are not required for profile completeness.';

commit;

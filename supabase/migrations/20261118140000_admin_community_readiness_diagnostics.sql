-- Admin-only aggregate diagnostics for legacy community recovery.
-- This intentionally returns counts only: no names, emails, orientations, or coordinates.
begin;

create or replace function public.get_admin_community_readiness()
returns table (
  total_profiles bigint,
  lgbtq_members bigint,
  straight_members bigint,
  community_selection_needed bigint,
  fresh_nearby_locations bigint,
  legacy_members_with_fresh_location bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.is_match_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  return query
  select
    count(*)::bigint,
    count(*) filter (
      where private.member_dating_community(p.id) = 'lgbtq'
    )::bigint,
    count(*) filter (
      where private.member_dating_community(p.id) = 'straight'
    )::bigint,
    count(*) filter (
      where private.member_dating_community(p.id) is null
    )::bigint,
    count(*) filter (
      where p.location_sharing is true
        and locations.nearby_latitude is not null
        and locations.nearby_longitude is not null
        and locations.nearby_updated_at >= now() - interval '7 days'
    )::bigint,
    count(*) filter (
      where private.member_dating_community(p.id) is null
        and p.location_sharing is true
        and locations.nearby_latitude is not null
        and locations.nearby_longitude is not null
        and locations.nearby_updated_at >= now() - interval '7 days'
    )::bigint
  from public.profiles p
  left join private.profile_locations locations
    on locations.user_id = p.id;
end;
$function$;

revoke all on function public.get_admin_community_readiness() from public, anon;
grant execute on function public.get_admin_community_readiness() to authenticated;

commit;

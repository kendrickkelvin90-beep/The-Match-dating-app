-- Do not expose the complete list of boosted member IDs to every signed-in user.
-- Return boost status only for members who are already eligible for this viewer's Discover feed.
revoke execute on function public.get_active_discover_boost_ids()\n  from public, anon, authenticated;

create or replace function public.get_active_discover_boost_ids(p_user_ids uuid[])
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_viewer_id uuid := auth.uid();
begin
  if v_viewer_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if coalesce(cardinality(p_user_ids), 0) > 100 then
    raise exception 'A maximum of 100 member IDs can be requested' using errcode = '22023';
  end if;

  return query
  select distinct boost.user_id
  from public.profile_boosts boost
  join (
    select eligible.user_id
    from public.matchmaking_eligible_candidate_ids() eligible
    join unnest(coalesce(p_user_ids, '{}'::uuid[])) requested(user_id)
      on requested.user_id = eligible.user_id
  ) visible on visible.user_id = boost.user_id
  where boost.starts_at <= now()
    and boost.ends_at > now();
end;
$function$;

revoke execute on function public.get_active_discover_boost_ids(uuid[])
  from public, anon;
grant execute on function public.get_active_discover_boost_ids(uuid[])
  to authenticated;

-- Server-side interest overlap scoring.
-- The candidate's interests are considered only after the existing secure
-- shared-details RPC confirms current Discover visibility and opt-in.
-- The browser receives a count and Jaccard percentage, never raw arrays.

begin;

create or replace function public.get_interest_match_scores(p_user_ids uuid[])
returns table(user_id uuid, shared_interest_count integer, interest_match_percent integer)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if coalesce(cardinality(p_user_ids), 0) > 100 then
    raise exception 'A maximum of 100 member IDs can be requested' using errcode = '22023';
  end if;

  return query
  with viewer_interests as (
    select coalesce((
      select details.interests from public.member_dating_details details
      where details.user_id = auth.uid()
    ), '{}'::text[]) as interests
  ),
  opted_in_visible_candidates as (
    select shared.user_id, shared.interests
    from public.get_shared_dating_details(p_user_ids) shared
    where shared.interests is not null
  ),
  overlap_counts as (
    select candidate.user_id,
      (
        select count(distinct candidate_interest.interest)::integer
        from unnest(candidate.interests) as candidate_interest(interest)
        where candidate_interest.interest = any(viewer.interests)
      ) as shared_count,
      (
        select count(distinct combined.interest)::integer
        from (
          select unnest(viewer.interests) as interest
          union
          select unnest(candidate.interests) as interest
        ) combined
      ) as union_count
    from opted_in_visible_candidates candidate
    cross join viewer_interests viewer
  )
  select overlap.user_id, overlap.shared_count,
    case when overlap.union_count = 0 then 0
      else round(100.0 * overlap.shared_count / overlap.union_count)::integer
    end
  from overlap_counts overlap;
end;
$function$;

revoke all on function public.get_interest_match_scores(uuid[]) from public, anon;
grant execute on function public.get_interest_match_scores(uuid[]) to authenticated;

comment on function public.get_interest_match_scores(uuid[]) is
  'Returns only shared-interest count and Jaccard overlap percentage for currently visible candidates who opted in to interest sharing. Never returns raw interest arrays.';

commit;

-- Explainable compatibility scoring using only candidate data they opted to share.
-- The viewer's own preferences remain private; only aggregate scores are returned.

begin;

create or replace function public.get_dating_compatibility_scores(p_user_ids uuid[])
returns table(
  user_id uuid,
  compatibility_percent integer,
  scored_dimensions integer,
  shared_interest_count integer,
  interest_match_percent integer,
  relationship_intention_match boolean,
  communication_style_match boolean,
  shared_language_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_viewer_interests text[] := '{}'::text[];
  v_viewer_relationship_intention text := 'Still figuring it out';
  v_viewer_communication_style text := 'Prefer not to say';
  v_viewer_languages text[] := '{}'::text[];
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if coalesce(cardinality(p_user_ids), 0) > 100 then
    raise exception 'A maximum of 100 member IDs can be requested' using errcode = '22023';
  end if;

  select details.interests,
         details.relationship_intention,
         details.communication_style,
         details.languages
    into v_viewer_interests,
         v_viewer_relationship_intention,
         v_viewer_communication_style,
         v_viewer_languages
  from public.member_dating_details details
  where details.user_id = auth.uid();

  if not found then
    return;
  end if;

  return query
  with candidate_rows as (
    select
      shared.user_id,
      shared.interests,
      extras.relationship_intention,
      extras.communication_style,
      extras.languages
    from public.get_shared_dating_details(p_user_ids) shared
    left join public.get_shared_profile_extras(p_user_ids) extras
      on extras.user_id = shared.user_id
  ),
  raw_metrics as (
    select
      candidate.user_id,
      candidate.interests,
      candidate.relationship_intention,
      candidate.communication_style,
      candidate.languages,
      case
        when candidate.interests is not null
         and (coalesce(cardinality(v_viewer_interests), 0) > 0
              or coalesce(cardinality(candidate.interests), 0) > 0)
        then 50 else 0
      end as interest_weight,
      (
        select count(distinct pg_catalog.lower(pg_catalog.btrim(candidate_interest.value)))::integer
        from pg_catalog.unnest(coalesce(candidate.interests, '{}'::text[])) as candidate_interest(value)
        where pg_catalog.lower(pg_catalog.btrim(candidate_interest.value)) = any(
          select pg_catalog.lower(pg_catalog.btrim(viewer_interest.value))
          from pg_catalog.unnest(coalesce(v_viewer_interests, '{}'::text[])) as viewer_interest(value)
        )
      ) as shared_interest_count,
      (
        select count(*)::integer
        from (
          select pg_catalog.lower(pg_catalog.btrim(viewer_interest.value)) as interest
          from pg_catalog.unnest(coalesce(v_viewer_interests, '{}'::text[])) as viewer_interest(value)
          union
          select pg_catalog.lower(pg_catalog.btrim(candidate_interest.value)) as interest
          from pg_catalog.unnest(coalesce(candidate.interests, '{}'::text[])) as candidate_interest(value)
        ) interest_union
      ) as interest_union_count,
      case
        when candidate.relationship_intention is not null
         and v_viewer_relationship_intention not in ('Prefer not to say','Still figuring it out')
         and candidate.relationship_intention not in ('Prefer not to say','Still figuring it out')
        then 25 else 0
      end as intention_weight,
      case
        when candidate.relationship_intention is not null
         and v_viewer_relationship_intention not in ('Prefer not to say','Still figuring it out')
         and candidate.relationship_intention not in ('Prefer not to say','Still figuring it out')
        then v_viewer_relationship_intention = candidate.relationship_intention
        else null
      end as intention_match,
      case
        when candidate.communication_style is not null
         and v_viewer_communication_style <> 'Prefer not to say'
         and candidate.communication_style <> 'Prefer not to say'
        then 15 else 0
      end as communication_weight,
      case
        when candidate.communication_style is not null
         and v_viewer_communication_style <> 'Prefer not to say'
         and candidate.communication_style <> 'Prefer not to say'
        then v_viewer_communication_style = candidate.communication_style
        else null
      end as communication_match,
      case
        when coalesce(cardinality(v_viewer_languages), 0) > 0
         and coalesce(cardinality(candidate.languages), 0) > 0
        then 10 else 0
      end as language_weight,
      (
        select count(distinct pg_catalog.lower(pg_catalog.btrim(candidate_language.value)))::integer
        from pg_catalog.unnest(coalesce(candidate.languages, '{}'::text[])) as candidate_language(value)
        where pg_catalog.lower(pg_catalog.btrim(candidate_language.value)) = any(
          select pg_catalog.lower(pg_catalog.btrim(viewer_language.value))
          from pg_catalog.unnest(coalesce(v_viewer_languages, '{}'::text[])) as viewer_language(value)
        )
      ) as shared_language_count,
      (
        select count(*)::integer
        from (
          select pg_catalog.lower(pg_catalog.btrim(viewer_language.value)) as language
          from pg_catalog.unnest(coalesce(v_viewer_languages, '{}'::text[])) as viewer_language(value)
          union
          select pg_catalog.lower(pg_catalog.btrim(candidate_language.value)) as language
          from pg_catalog.unnest(coalesce(candidate.languages, '{}'::text[])) as candidate_language(value)
        ) language_union
      ) as language_union_count
    from candidate_rows candidate
  ),
  scored as (
    select
      metrics.*,
      (metrics.interest_weight + metrics.intention_weight
       + metrics.communication_weight + metrics.language_weight) as total_weight,
      (
        case when metrics.interest_weight > 0 and metrics.interest_union_count > 0
          then 50.0 * metrics.shared_interest_count / metrics.interest_union_count else 0 end
        + case when metrics.intention_weight > 0 and metrics.intention_match then 25.0 else 0 end
        + case when metrics.communication_weight > 0 and metrics.communication_match then 15.0 else 0 end
        + case when metrics.language_weight > 0 and metrics.language_union_count > 0
          then 10.0 * metrics.shared_language_count / metrics.language_union_count else 0 end
      ) as weighted_score,
      (
        (metrics.interest_weight > 0)::integer
        + (metrics.intention_weight > 0)::integer
        + (metrics.communication_weight > 0)::integer
        + (metrics.language_weight > 0)::integer
      ) as dimension_count
    from raw_metrics metrics
  )
  select
    scored.user_id,
    round(100.0 * scored.weighted_score / scored.total_weight)::integer,
    scored.dimension_count,
    scored.shared_interest_count,
    case when scored.interest_union_count > 0
      then round(100.0 * scored.shared_interest_count / scored.interest_union_count)::integer
      else 0 end,
    scored.intention_match,
    scored.communication_match,
    scored.shared_language_count
  from scored
  where scored.total_weight > 0;
end;
$function$;

revoke all on function public.get_dating_compatibility_scores(uuid[]) from public, anon;
grant execute on function public.get_dating_compatibility_scores(uuid[]) to authenticated;

comment on function public.get_dating_compatibility_scores(uuid[]) is
  'Returns an explainable compatibility percentage and aggregate overlap indicators. Candidate details are included only when that candidate has opted in to the relevant sharing controls; raw profile fields and arrays are never returned.';

commit;

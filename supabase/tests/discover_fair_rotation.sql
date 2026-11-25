\set ON_ERROR_STOP on

-- Verify the deployed candidate-ID RPC uses a viewer-specific rotating hash
-- over the full eligible CTE before applying the unchanged 100-result cap.
do $fair_rotation$
declare
  function_sql text;
begin
  function_sql := pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.matchmaking_eligible_candidate_ids(double precision,integer,integer,text,text,text[],boolean,text,integer)'::regprocedure
  ));

  if position('md5' in function_sql) = 0
     or position('21600' in function_sql) = 0 then
    raise exception 'Discover candidate selection is missing its six-hour viewer-specific hash rotation';
  end if;

  if position('order by candidate_id' in function_sql) > 0 then
    raise exception 'Discover still uses permanent UUID-first candidate ordering';
  end if;

  if position('p_max_results' in function_sql) = 0
     or position('limit' in function_sql) = 0
     or position('100' in function_sql) = 0 then
    raise exception 'Discover must preserve its existing maximum 100 candidate response';
  end if;

  if position('private.member_dating_community(candidate.id)' in function_sql) = 0
     or position('private.member_meets_partner_preferences(candidate.id, v_viewer_id)' in function_sql) = 0 then
    raise exception 'Discover rotation must preserve dating-lane and reciprocal compatibility filters';
  end if;
end;
$fair_rotation$;

select 'fair Discover candidate rotation tests passed' as result;

-- Unassigned profiles are eligible for read-only Discover visibility in either lane.
do $unassigned_discover$
declare
  discover_sql text;
  candidate_sql text;
  interaction_sql text;
  like_sql text;
  pass_sql text;
begin
  discover_sql := pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.discover_profiles_secure(double precision,integer,integer,text)'::regprocedure
  ));
  candidate_sql := pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.matchmaking_eligible_candidate_ids(double precision,integer,integer,text,text,text[],boolean,text,integer)'::regprocedure
  ));
  interaction_sql := pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.member_can_interact_with_discover_profile(uuid)'::regprocedure
  ));
  like_sql := pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'private.enforce_same_dating_community_on_like()'::regprocedure
  ));
  pass_sql := pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'private.enforce_same_dating_community_on_pass()'::regprocedure
  ));

  if position('member_dating_community(p.id) is null' in discover_sql) = 0
     or position('member_dating_community(candidate.id) is null' in candidate_sql) = 0 then
    raise exception 'Unassigned profiles are not included in the Discover candidate pool';
  end if;

  if position('member_dating_community(target_user_id)' in interaction_sql) = 0
     or position('is true' in interaction_sql) = 0 then
    raise exception 'Discover interaction helper is missing its same-lane guard';
  end if;

  if position('v_liker_lane is null or v_liked_lane is null' in like_sql) = 0
     or position('v_passer_lane is null or v_passed_lane is null' in pass_sql) = 0 then
    raise exception 'Unassigned members must remain blocked from likes and passes';
  end if;
end;
$unassigned_discover$;

select 'unassigned Discover read-only tests passed' as result;

\set ON_ERROR_STOP on

-- Verify the deployed candidate-ID RPC uses a viewer-specific rotating hash
-- over the full eligible CTE before applying the unchanged 100-result cap.
do $fair_rotation$
declare
  function_sql text;
begin
  function_sql := pg_catalog.pg_get_functiondef(
    'public.matchmaking_eligible_candidate_ids(double precision,integer,integer,text,text,text[],boolean,text,integer)'::regprocedure
  );

  if position('pg_catalog.md5' in function_sql) = 0
     or position('pg_catalog.date_part' in function_sql) = 0
     or position('21600' in function_sql) = 0 then
    raise exception 'Discover candidate selection is missing its six-hour viewer-specific hash rotation';
  end if;

  if position('order by candidate_id' in function_sql) > 0 then
    raise exception 'Discover still uses permanent UUID-first candidate ordering';
  end if;

  if position('limit greatest(1, least(coalesce(p_max_results, 100), 100))' in function_sql) = 0 then
    raise exception 'Discover must preserve its existing maximum 100 candidate response';
  end if;

  if position('private.member_dating_community(candidate.id)' in function_sql) = 0
     or position('private.member_meets_partner_preferences(candidate.id, v_viewer_id)' in function_sql) = 0 then
    raise exception 'Discover rotation must preserve dating-lane and reciprocal compatibility filters';
  end if;
end;
$fair_rotation$;

select 'fair Discover candidate rotation tests passed' as result;

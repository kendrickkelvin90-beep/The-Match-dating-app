alter table public.profiles
  add column if not exists profile_paused boolean not null default false;

do $migration$
declare
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'matchmaking_eligible_candidate_ids'
    and pg_get_function_identity_arguments(p.oid) =
      'p_max_distance_km double precision, p_min_age integer, p_max_age integer, p_city text, p_show_me text, p_role_preferences text[], p_verified_only boolean, p_connection_goal text, p_max_results integer';

  if v_definition is null then
    raise exception 'Expected matchmaking eligibility function was not found';
  end if;

  if position('candidate.profile_paused' in v_definition) > 0 then
    return;
  end if;

  v_updated := replace(
    v_definition,
    'and public.is_match_profile_complete(candidate.id)',
    'and candidate.profile_paused = false
      and public.is_match_profile_complete(candidate.id)'
  );

  if v_updated = v_definition then
    raise exception 'Could not locate candidate eligibility clause; refusing partial migration';
  end if;

  execute v_updated;
end
$migration$;

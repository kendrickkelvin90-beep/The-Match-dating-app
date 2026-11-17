-- Focused regression checks for the Pause Profile control.
-- Run after 20261117190000_profile_pause_discovery_control.sql.
DO $test$
DECLARE
  v_default text;
  v_definition text;
BEGIN
  SELECT column_default
    INTO v_default
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'profiles'
    AND column_name = 'profile_paused';

  IF v_default IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'profile_paused must default to false; got %', v_default;
  END IF;

  SELECT pg_get_functiondef(
    'public.matchmaking_eligible_candidate_ids(double precision,integer,integer,text,text,text[],boolean,text,integer)'::regprocedure
  ) INTO v_definition;

  IF position('candidate.profile_paused' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Paused profiles are not excluded by server-side Discover eligibility';
  END IF;

  IF position('candidate.profile_paused = false' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Discover eligibility must require profile_paused = false';
  END IF;

  RAISE NOTICE 'Pause Profile database regression checks passed';
END
$test$;

-- Regression checks for optional pronouns and Discover-only visibility.
DO $test$
DECLARE
  v_visibility_default text;
  v_pronouns_nullable text;
  v_definition text;
BEGIN
  SELECT column_default INTO v_visibility_default
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='profiles' AND column_name='discover_visibility';
  IF v_visibility_default IS DISTINCT FROM '''everyone''::text' THEN
    RAISE EXCEPTION 'discover_visibility must default to everyone; got %', v_visibility_default;
  END IF;

  SELECT is_nullable INTO v_pronouns_nullable
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='profiles' AND column_name='pronouns';
  IF v_pronouns_nullable IS DISTINCT FROM 'YES' THEN
    RAISE EXCEPTION 'pronouns must remain optional';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(
    'public.matchmaking_eligible_candidate_ids(double precision,integer,integer,text,text,text[],boolean,text,integer)'::regprocedure
  ) INTO v_definition;

  IF pg_catalog.strpos(v_definition, 'candidate.discover_visibility') = 0
     OR pg_catalog.strpos(v_definition, '''everyone''') = 0 THEN
    RAISE EXCEPTION 'Server-side Discover eligibility does not enforce discover_visibility';
  END IF;

  RAISE NOTICE 'Pronouns and Discover visibility regression checks passed';
END
$test$;

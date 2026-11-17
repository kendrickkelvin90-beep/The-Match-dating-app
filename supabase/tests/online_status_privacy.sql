-- Regression checks for opt-out from live online presence.
DO $test$
DECLARE
  v_default text;
  v_nullable text;
BEGIN
  SELECT column_default, is_nullable
    INTO v_default, v_nullable
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='profiles' AND column_name='show_online_status';

  IF v_default IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'show_online_status must default to true; got %', v_default;
  END IF;
  IF v_nullable IS DISTINCT FROM 'NO' THEN
    RAISE EXCEPTION 'show_online_status must be non-null';
  END IF;
  RAISE NOTICE 'Online status privacy schema checks passed';
END
$test$;

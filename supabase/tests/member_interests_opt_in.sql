\set ON_ERROR_STOP on

-- Seed test identities as the database owner before exercising RLS.
insert into auth.users (id) values
  ('00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000002');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', false);

do $test$
declare
  v_count integer;
  v_enabled boolean;
  v_version text;
  v_consented_at timestamptz;
  v_original_consent timestamptz;
  v_extra_code text;
  v_rows integer;
begin
  select count(*) into v_count from public.interest_catalog;
  if v_count <> 30 then
    raise exception 'Expected 30 curated interest choices, got %', v_count;
  end if;

  insert into public.member_interest_sharing (user_id)
  values (auth.uid());

  select share_for_matching into v_enabled
  from public.member_interest_sharing where user_id = auth.uid();
  if v_enabled is distinct from false then
    raise exception 'Interest sharing must default to off';
  end if;

  update public.member_interest_sharing
  set share_for_matching = true
  where user_id = auth.uid();

  select consent_version, consented_at
    into v_version, v_consented_at
  from public.member_interest_sharing where user_id = auth.uid();

  if v_version <> 'v1' or v_consented_at is null then
    raise exception 'Opt-in must record the current consent version and server timestamp';
  end if;
  v_original_consent := v_consented_at;

  update public.member_interest_sharing
  set consent_version = 'forged', consented_at = '2000-01-01T00:00:00Z'
  where user_id = auth.uid();

  select consent_version, consented_at
    into v_version, v_consented_at
  from public.member_interest_sharing where user_id = auth.uid();

  if v_version <> 'v1' or v_consented_at <> v_original_consent then
    raise exception 'A member must not be able to rewrite consent evidence while opted in';
  end if;

  insert into public.member_interests (user_id, interest_code)
  values (auth.uid(), 'music');

  select count(*) into v_count from public.member_interests where user_id = auth.uid();
  if v_count <> 1 then
    raise exception 'Member should be able to read their own selected interest';
  end if;

  -- Switch identity: member B must not see or alter member A's data.
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', false);

  select count(*) into v_count
  from public.member_interests
  where user_id = '00000000-0000-4000-8000-000000000001';
  if v_count <> 0 then
    raise exception 'Member B can read member A interests';
  end if;

  select count(*) into v_count
  from public.member_interest_sharing
  where user_id = '00000000-0000-4000-8000-000000000001';
  if v_count <> 0 then
    raise exception 'Member B can read member A sharing preference';
  end if;

  update public.member_interest_sharing
  set share_for_matching = false
  where user_id = '00000000-0000-4000-8000-000000000001';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'Member B changed member A sharing preference';
  end if;

  begin
    insert into public.member_interests (user_id, interest_code)
    values ('00000000-0000-4000-8000-000000000001', 'movies');
    raise exception 'Member B unexpectedly inserted an interest for member A';
  exception when insufficient_privilege then
    null;
  end;

  insert into public.member_interests (user_id, interest_code)
  values (auth.uid(), 'music');

  select count(*) into v_count from public.member_interests where user_id = auth.uid();
  if v_count <> 1 then
    raise exception 'Member B should be able to manage their own interests';
  end if;

  -- Return to member A and test the hard 20-interest cap.
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', false);

  insert into public.member_interests (user_id, interest_code)
  select auth.uid(), code
  from public.interest_catalog
  where code <> 'music'
  order by sort_order
  limit 19;

  select count(*) into v_count from public.member_interests where user_id = auth.uid();
  if v_count <> 20 then
    raise exception 'Expected exactly 20 selected interests, got %', v_count;
  end if;

  select code into v_extra_code
  from public.interest_catalog
  where code not in (
    select interest_code from public.member_interests where user_id = auth.uid()
  )
  order by sort_order
  limit 1;

  begin
    insert into public.member_interests (user_id, interest_code)
    values (auth.uid(), v_extra_code);
    raise exception 'The 21st interest was unexpectedly accepted';
  exception when check_violation then
    null;
  end;

  -- Opt-out must clear consent evidence.
  update public.member_interest_sharing
  set share_for_matching = false
  where user_id = auth.uid();

  select share_for_matching, consent_version, consented_at
    into v_enabled, v_version, v_consented_at
  from public.member_interest_sharing where user_id = auth.uid();

  if v_enabled is distinct from false or v_version is not null or v_consented_at is not null then
    raise exception 'Opt-out must clear sharing consent fields';
  end if;

  -- Catalog is read-only to clients.
  begin
    insert into public.interest_catalog (code, label, category)
    values ('client_insert', 'Client insert', 'culture');
    raise exception 'Authenticated member unexpectedly modified the catalog';
  exception when insufficient_privilege then
    null;
  end;
end;
$test$;

reset role;
set role anon;

do $anon_test$
begin
  begin
    perform count(*) from public.interest_catalog;
    raise exception 'Anonymous role unexpectedly read the interest catalog';
  exception when insufficient_privilege then
    null;
  end;
end;
$anon_test$;

reset role;

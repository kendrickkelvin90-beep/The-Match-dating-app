-- OPTIONAL ACTIVATION STEP. Do not run until the advertising migration,
-- Edge Function guards and member regression tests have been approved.
-- This project was inspected and currently has no authenticator pre-request
-- function. Stop rather than overwrite one if another workflow adds it later.
do $guard$
begin
  if exists (
    select 1
    from pg_catalog.pg_db_role_setting s
    where exists (
        select 1 from unnest(s.setconfig) cfg
        where cfg like 'pgrst.db_pre_request=%'
      )
  ) then
    raise exception 'authenticator already has pgrst.db_pre_request configured; review and compose the existing function instead of overwriting it';
  end if;
end;
$guard$;

alter role authenticator set pgrst.db_pre_request = 'public.match_advertiser_api_guard';
notify pgrst, 'reload config';

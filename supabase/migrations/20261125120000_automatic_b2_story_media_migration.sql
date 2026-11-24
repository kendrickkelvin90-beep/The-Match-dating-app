-- Run legacy Story media migration in the background without an administrator session.
-- The Edge Function validates a high-entropy token stored in Supabase Vault.
-- Source Supabase Storage objects are retained; only database pointers change after B2 upload succeeds.
begin;

create table if not exists public.b2_media_migration_failures (
  category text not null check (category in ('stories','profile_photos','chat_media','verification_selfies','event_posters')),
  record_id uuid not null,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  next_retry_at timestamptz,
  failed_permanently boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (category, record_id)
);

alter table public.b2_media_migration_failures enable row level security;
revoke all on public.b2_media_migration_failures from public, anon;
grant select on public.b2_media_migration_failures to authenticated;
grant all on public.b2_media_migration_failures to service_role;

drop policy if exists b2_media_migration_failures_admin_read on public.b2_media_migration_failures;
create policy b2_media_migration_failures_admin_read
  on public.b2_media_migration_failures
  for select to authenticated
  using (public.is_match_admin());

create or replace function public.verify_b2_story_migration_cron_signature(
  p_timestamp bigint,
  p_category text,
  p_limit integer,
  p_signature text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_expected text;
  v_token text;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    return false;
  end if;
  if p_category is distinct from 'stories' or p_limit is distinct from 2 or p_signature is null then
    return false;
  end if;
  if p_timestamp is null
     or abs(extract(epoch from clock_timestamp())::bigint - p_timestamp) > 300 then
    return false;
  end if;

  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name = 'b2_story_migration_cron_token';

  if v_token is null then return false; end if;
  v_expected := encode(
    extensions.hmac(p_timestamp::text || ':' || p_category || ':' || p_limit::text, v_token, 'sha256'),
    'hex'
  );
  return lower(p_signature) = v_expected;
end;
$function$;

revoke all on function public.verify_b2_story_migration_cron_signature(bigint,text,integer,text)
  from public, anon, authenticated;
grant execute on function public.verify_b2_story_migration_cron_signature(bigint,text,integer,text)
  to service_role;

create or replace function public.complete_b2_story_migration()
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;

  -- Keep the schedule alive while any legacy Story is still eligible for a
  -- future retry. Stop only when all remaining legacy records are marked as
  -- permanently failed; their originals remain in Supabase for admin review.
  if exists (
    select 1
    from public.stories s
    left join public.b2_media_migration_failures f
      on f.category = 'stories' and f.record_id = s.id
    where s.media_url is not null
      and s.media_url not like 'b2://%'
      and s.expires_at > now()
      and (f.record_id is null or not f.failed_permanently)
  ) then
    return false;
  end if;

  perform cron.unschedule('automatic-b2-story-media-migration');
  return true;
end;
$function$;

revoke all on function public.complete_b2_story_migration() from public, anon, authenticated;
grant execute on function public.complete_b2_story_migration() to service_role;

-- Generate the scheduler token inside the database. It is never written to GitHub
-- or returned to the application. The publishable key is public by design.
do $vault$
begin
  if not exists (
    select 1 from vault.secrets where name = 'b2_story_migration_cron_token'
  ) then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'b2_story_migration_cron_token',
      'Private bearer token used only by the scheduled B2 Story migration worker',
      null
    );
  end if;

  if not exists (
    select 1 from vault.secrets where name = 'match_b2_story_scheduler_apikey'
  ) then
    perform vault.create_secret(
      'sb_publishable_5OirCcmy8L5n3isPvi-P0w_Dgeb13U_',
      'match_b2_story_scheduler_apikey',
      'Public Supabase publishable key used by pg_cron to reach the Edge Function',
      null
    );
  end if;

  if not exists (
    select 1 from vault.secrets where name = 'b2_story_migration_cluster_id'
  ) then
    perform vault.create_secret(
      (pg_control_system()).system_identifier::text,
      'b2_story_migration_cluster_id',
      'Database-cluster identity guard so copied preview branches cannot call the production migration endpoint',
      null
    );
  end if;
end;
$vault$;

-- The database invokes the worker once a minute, but only while a Story is
-- due for migration or retry. Failed records back off and are retried up to
-- five times; permanently failed items remain in Supabase and are visible to
-- administrators for investigation. The job stops when no retryable rows remain.
select cron.schedule(
  'automatic-b2-story-media-migration',
  '* * * * *',
  $job$
    with scheduler_secrets as (
      select
        (select decrypted_secret from vault.decrypted_secrets where name = 'b2_story_migration_cron_token') as scheduler_token,
        (select decrypted_secret from vault.decrypted_secrets where name = 'match_b2_story_scheduler_apikey') as public_api_key,
        (select decrypted_secret from vault.decrypted_secrets where name = 'b2_story_migration_cluster_id') as saved_cluster_id,
        (pg_control_system()).system_identifier::text as current_cluster_id,
        floor(extract(epoch from clock_timestamp()))::bigint as request_timestamp
    )
    select case
      when not exists (
        select 1
        from public.stories s
        left join public.b2_media_migration_failures f
          on f.category = 'stories' and f.record_id = s.id
        where s.media_url is not null
          and s.media_url not like 'b2://%'
          and s.expires_at > now()
          and (f.record_id is null or not f.failed_permanently)
      ) then cron.unschedule('automatic-b2-story-media-migration')::text
      when exists (
        select 1 from scheduler_secrets
        where saved_cluster_id is distinct from current_cluster_id
      ) then cron.unschedule('automatic-b2-story-media-migration')::text
      when exists (
        select 1
        from public.stories s
        left join public.b2_media_migration_failures f
          on f.category = 'stories' and f.record_id = s.id
        where s.media_url is not null
          and s.media_url not like 'b2://%'
          and s.expires_at > now()
          and (
            f.record_id is null
            or (
              not f.failed_permanently
              and (f.next_retry_at is null or f.next_retry_at <= now())
            )
          )
      ) then (
        select net.http_post(
          url := 'https://rxbdmgzmwhjnkcclyrcq.supabase.co/functions/v1/b2-media-migrate',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'apikey', scheduler_secrets.public_api_key,
            'Authorization', 'Bearer ' || scheduler_secrets.public_api_key,
            'x-match-cron-timestamp', scheduler_secrets.request_timestamp::text,
            'x-match-cron-signature', encode(
              extensions.hmac(
                scheduler_secrets.request_timestamp::text || ':stories:2',
                scheduler_secrets.scheduler_token,
                'sha256'
              ),
              'hex'
            )
          ),
          body := '{"category":"stories","limit":2}'::jsonb,
          timeout_milliseconds := 55000
        )::text
        from scheduler_secrets
        where scheduler_secrets.scheduler_token is not null
          and scheduler_secrets.public_api_key is not null
          and scheduler_secrets.saved_cluster_id = scheduler_secrets.current_cluster_id
      )
      else null
    end;
  $job$
);

commit;

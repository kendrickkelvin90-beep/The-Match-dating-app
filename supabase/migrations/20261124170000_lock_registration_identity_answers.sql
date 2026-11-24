-- Lock identity and dating-lane answers to the registration choices.
-- Users may update other onboarding answers, but cannot change the values
-- that determine their dating lane or reciprocal gender compatibility.

begin;

-- Existing members already supplied these values in their profile. Copy them
-- into their private onboarding record before locking the registration fields.
update public.member_onboarding onboarding
set answers = onboarding.answers || jsonb_strip_nulls(jsonb_build_object(
  'gender_identity', profile.gender_identity,
  'interested_in', profile.interested_in
))
from public.profiles profile
where onboarding.user_id = profile.id
  and (
    (nullif(onboarding.answers ->> 'gender_identity', '') is null and profile.gender_identity is not null)
    or (nullif(onboarding.answers ->> 'interested_in', '') is null and profile.interested_in is not null)
  );

create or replace function private.prevent_registration_identity_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  protected_key text;
begin
  if auth.uid() is null or auth.uid() <> old.user_id then
    return new;
  end if;

  foreach protected_key in array array[
    'sexual_orientation',
    'gender_identity',
    'interested_in'
  ]
  loop
    if nullif(old.answers ->> protected_key, '') is not null
      and new.answers ->> protected_key is distinct from old.answers ->> protected_key
    then
      raise exception 'Registration identity answers cannot be changed after account creation.'
        using errcode = '42501';
    end if;
  end loop;

  return new;
end;
$function$;

drop trigger if exists prevent_registration_identity_changes
  on public.member_onboarding;
create trigger prevent_registration_identity_changes
before update of answers on public.member_onboarding
for each row execute function private.prevent_registration_identity_changes();

create or replace function private.prevent_profile_registration_identity_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  registration_answers jsonb;
begin
  if auth.uid() is null or auth.uid() <> new.id then
    return new;
  end if;

  if tg_op = 'INSERT' then
    select onboarding.answers
      into registration_answers
    from public.member_onboarding onboarding
    where onboarding.user_id = new.id;

    if registration_answers ? 'gender_identity'
      and nullif(registration_answers ->> 'gender_identity', '') is not null
      and new.gender_identity is distinct from registration_answers ->> 'gender_identity'
    then
      raise exception 'Profile gender identity must match the registration answer.'
        using errcode = '42501';
    end if;

    if registration_answers ? 'interested_in'
      and nullif(registration_answers ->> 'interested_in', '') is not null
      and new.interested_in is distinct from registration_answers ->> 'interested_in'
    then
      raise exception 'Dating preferences must match the registration answer.'
        using errcode = '42501';
    end if;

    return new;
  end if;

  if old.gender_identity is distinct from new.gender_identity
    or old.interested_in is distinct from new.interested_in
  then
    raise exception 'Gender identity and dating preferences cannot be changed from profile settings.'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

drop trigger if exists prevent_profile_registration_identity_changes
  on public.profiles;
create trigger prevent_profile_registration_identity_changes
before insert or update of gender_identity, interested_in on public.profiles
for each row execute function private.prevent_profile_registration_identity_changes();

revoke all on function private.prevent_registration_identity_changes()
  from public, anon, authenticated;
revoke all on function private.prevent_profile_registration_identity_changes()
  from public, anon, authenticated;

commit;

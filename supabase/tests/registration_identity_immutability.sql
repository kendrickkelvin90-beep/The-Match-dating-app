\set ON_ERROR_STOP on

-- User 1 is a bisexual LGBTQ+ fixture after the lane-separation regression.
-- Authenticated members must not be able to change their registration answers
-- or alter the matching fields stored on their profile.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);

do $registration_identity_lock$
begin
  begin
    update public.member_onboarding
    set answers = jsonb_set(answers, '{sexual_orientation}', '"Straight / heterosexual"')
    where user_id = '00000000-0000-4000-8000-000000000001';
    raise exception 'Expected sexual-orientation change to be rejected';
  exception
    when insufficient_privilege then
      if sqlerrm not like '%Registration identity answers cannot be changed%' then
        raise;
      end if;
  end;

  begin
    update public.member_onboarding
    set answers = jsonb_set(answers, '{gender_identity}', '"Woman"')
    where user_id = '00000000-0000-4000-8000-000000000001';
    raise exception 'Expected gender-identity change to be rejected';
  exception
    when insufficient_privilege then
      if sqlerrm not like '%Registration identity answers cannot be changed%' then
        raise;
      end if;
  end;

  begin
    update public.profiles
    set gender_identity = case
      when gender_identity = 'Man' then 'Woman'
      else 'Man'
    end
    where id = '00000000-0000-4000-8000-000000000001';
    raise exception 'Expected profile gender-identity change to be rejected';
  exception
    when insufficient_privilege then
      if sqlerrm not like '%Gender identity and dating preferences cannot be changed%' then
        raise;
      end if;
  end;

  begin
    update public.profiles
    set interested_in = case
      when interested_in = 'Men' then 'Women'
      else 'Men'
    end
    where id = '00000000-0000-4000-8000-000000000001';
    raise exception 'Expected profile dating-preference change to be rejected';
  exception
    when insufficient_privilege then
      if sqlerrm not like '%Gender identity and dating preferences cannot be changed%' then
        raise;
      end if;
  end;
end;
$registration_identity_lock$;

-- A legacy member whose orientation answer is genuinely missing may complete
-- it once. The same trigger must still reject changes after that first save.
alter table public.member_onboarding
  disable trigger prevent_registration_identity_changes;
update public.member_onboarding
set answers = answers - 'sexual_orientation'
where user_id = '00000000-0000-4000-8000-000000000015';
alter table public.member_onboarding
  enable trigger prevent_registration_identity_changes;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000015',false);
update public.member_onboarding
set answers = answers || '{"sexual_orientation":"Gay"}'::jsonb
where user_id = '00000000-0000-4000-8000-000000000015';

do $missing_orientation_recovery$
begin
  if private.member_dating_community('00000000-0000-4000-8000-000000000015') <> 'lgbtq' then
    raise exception 'A member completing a missing orientation must be assigned to the correct lane';
  end if;
end;
$missing_orientation_recovery$;

select 'registration identity immutability and missing-orientation recovery tests passed' as result;

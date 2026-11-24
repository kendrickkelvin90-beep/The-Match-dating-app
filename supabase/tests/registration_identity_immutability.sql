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

select 'registration identity immutability tests passed' as result;

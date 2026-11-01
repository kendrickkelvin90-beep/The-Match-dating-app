-- Stop granting 1 Premium day to newly referred members.
-- Keep the referrer's existing 10- and 20-referral milestone rewards.
-- Previously granted rewards and memberships are intentionally left unchanged.

CREATE OR REPLACE FUNCTION private.process_referral_main_photo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_referral public.referrals%ROWTYPE;
  v_reward_id UUID;
  v_success_count INTEGER;
BEGIN
  IF NEW.position <> 0 THEN
    RETURN NEW;
  END IF;

  SELECT *
  INTO v_referral
  FROM public.referrals
  WHERE referred_user_id = NEW.user_id
    AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  UPDATE public.referrals
  SET status = 'successful',
      qualified_at = now()
  WHERE id = v_referral.id
    AND status = 'pending';

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- No Premium reward is granted to the newly referred member.

  -- Count successful referrals after qualifying this referral.
  SELECT count(*) INTO v_success_count
  FROM public.referrals
  WHERE referrer_id = v_referral.referrer_id
    AND status = 'successful';

  -- Milestone: 10 successful referrals = 3 Premium days, once only.
  IF v_success_count >= 10 THEN
    v_reward_id := NULL;

    INSERT INTO public.referral_rewards
      (recipient_id, referral_id, reward_type, premium_days, milestone_count)
    VALUES
      (v_referral.referrer_id, NULL, 'milestone', 3, 10)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_reward_id;

    IF v_reward_id IS NOT NULL THEN
      INSERT INTO public.premium_memberships
        (user_id, premium_until, premium_started_at)
      VALUES
        (v_referral.referrer_id, now() + interval '3 days', now())
      ON CONFLICT (user_id) DO UPDATE
        SET premium_until = greatest(
          public.premium_memberships.premium_until, now()
        ) + interval '3 days',
        premium_started_at = coalesce(
          public.premium_memberships.premium_started_at, now()
        );
    END IF;
  END IF;

  -- Milestone: 20 successful referrals = 7 Premium days, once only.
  IF v_success_count >= 20 THEN
    v_reward_id := NULL;

    INSERT INTO public.referral_rewards
      (recipient_id, referral_id, reward_type, premium_days, milestone_count)
    VALUES
      (v_referral.referrer_id, NULL, 'milestone', 7, 20)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_reward_id;

    IF v_reward_id IS NOT NULL THEN
      INSERT INTO public.premium_memberships
        (user_id, premium_until, premium_started_at)
      VALUES
        (v_referral.referrer_id, now() + interval '7 days', now())
      ON CONFLICT (user_id) DO UPDATE
        SET premium_until = greatest(
          public.premium_memberships.premium_until, now()
        ) + interval '7 days',
        premium_started_at = coalesce(
          public.premium_memberships.premium_started_at, now()
        );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

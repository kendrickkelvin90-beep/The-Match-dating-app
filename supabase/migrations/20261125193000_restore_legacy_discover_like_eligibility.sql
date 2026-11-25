-- Restore Discover interaction eligibility for existing profiles created before
-- member_onboarding was introduced. Explicit registration answers always win;
-- legacy profile fields are used only when no explicit onboarding lane exists.
create or replace function private.member_dating_community(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    case
      when normalized.orientation in (
        'straight / heterosexual',
        'straight',
        'heterosexual',
        'heterosexual / straight',
        'hetero'
      ) then 'straight'
      when normalized.orientation is not null
        and normalized.orientation not in (
          'prefer not to say',
          'prefer not to disclose',
          'rather not say',
          'not disclosed',
          'not listed',
          'unknown'
        ) then 'lgbtq'
      when onboarding.answers ->> 'dating_community' in ('straight', 'lgbtq')
        then onboarding.answers ->> 'dating_community'
      else null
    end,
    case
      when lower(btrim(coalesce(profile.gender_identity, ''))) in (
        'genderqueer', 'non-binary', 'nonbinary', 'trans man', 'trans woman',
        'transgender man', 'transgender woman', 'transgender', 'agender',
        'genderfluid', 'gender fluid', 'homme'
      ) then 'lgbtq'
      when lower(btrim(coalesce(profile.gender_identity, ''))) = 'man'
        and lower(btrim(coalesce(profile.interested_in, ''))) in ('men', 'all genders', 'men and women', 'both men and women', 'tous les genres')
        then 'lgbtq'
      when lower(btrim(coalesce(profile.gender_identity, ''))) = 'woman'
        and lower(btrim(coalesce(profile.interested_in, ''))) in ('women', 'all genders', 'men and women', 'both men and women', 'tous les genres')
        then 'lgbtq'
      when lower(btrim(coalesce(profile.gender_identity, ''))) = 'man'
        and lower(btrim(coalesce(profile.interested_in, ''))) in ('women', 'woman')
        then 'straight'
      when lower(btrim(coalesce(profile.gender_identity, ''))) = 'woman'
        and lower(btrim(coalesce(profile.interested_in, ''))) in ('men', 'man')
        then 'straight'
      else null
    end
  )
  from public.profiles profile
  left join public.member_onboarding onboarding
    on onboarding.user_id = profile.id
  cross join lateral (
    select nullif(
      lower(btrim(coalesce(onboarding.answers ->> 'sexual_orientation', ''))),
      ''
    ) as orientation
  ) normalized
  where profile.id = p_user_id;
$function$;

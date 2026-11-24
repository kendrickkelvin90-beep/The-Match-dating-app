-- Automatically assign separate dating lanes from each member's existing
-- sexual-orientation answer. No new signup community selector is required.
-- Reciprocal gender preferences, blocks, moderation, and existing connections
-- remain protected. Existing cross-lane matches/conversations are preserved.

begin;

create or replace function private.member_dating_community(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select case
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
  end
  from public.member_onboarding onboarding
  cross join lateral (
    select nullif(
      pg_catalog.lower(pg_catalog.btrim(coalesce(onboarding.answers ->> 'sexual_orientation', ''))),
      ''
    ) as orientation
  ) normalized
  where onboarding.user_id = p_user_id;
$function$;

revoke all on function private.member_dating_community(uuid)
  from public, anon, authenticated;

comment on function private.member_dating_community(uuid) is
  'Returns a private dating lane derived from sexual_orientation: heterosexual members are in the straight lane; other disclosed orientations are in the LGBTQ+ lane. Legacy saved community is used only when orientation is missing or intentionally undisclosed.';

-- Preserve established mutual matches and conversations across a later lane
-- classification change, but keep all new discovery within the same lane.
create or replace function public.can_interact_with_member(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and target_user_id is not null
    and target_user_id <> auth.uid()
    and not exists (
      select 1
      from public.member_moderation moderation
      where moderation.user_id in (auth.uid(), target_user_id)
        and (
          moderation.status = 'banned'
          or (
            moderation.status = 'suspended'
            and moderation.expires_at > pg_catalog.now()
          )
        )
    )
    and not exists (
      select 1
      from public.member_blocks block_record
      where (block_record.blocker_id = auth.uid() and block_record.blocked_id = target_user_id)
         or (block_record.blocker_id = target_user_id and block_record.blocked_id = auth.uid())
    )
    and (
      (
        private.member_dating_community(auth.uid()) is not null
        and private.member_dating_community(target_user_id) =
            private.member_dating_community(auth.uid())
      )
      or exists (
        select 1
        from public.likes sent_like
        join public.likes received_like
          on received_like.liker_id = sent_like.liked_id
         and received_like.liked_id = sent_like.liker_id
        where sent_like.liker_id = auth.uid()
          and sent_like.liked_id = target_user_id
      )
      or exists (
        select 1
        from public.messages existing_message
        where (existing_message.sender_id = auth.uid()
               and existing_message.receiver_id = target_user_id)
           or (existing_message.sender_id = target_user_id
               and existing_message.receiver_id = auth.uid())
      )
    );
$function$;

revoke all on function public.can_interact_with_member(uuid) from public, anon;
grant execute on function public.can_interact_with_member(uuid) to authenticated;

-- Secure Discover itself (not only the optional candidate-ID helper) so no
-- direct RPC call can expose a profile from the other dating lane or a
-- one-sided gender-preference match.
create or replace function public.discover_profiles_secure(
  p_max_distance_km double precision default 20050,
  p_min_age integer default 18,
  p_max_age integer default 79,
  p_city text default null
)
returns table(
  id uuid,
  display_name text,
  age smallint,
  gender_identity text,
  interested_in text,
  bio text,
  city text,
  is_verified boolean,
  sexual_roles text[],
  verification_level text,
  distance_km double precision
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    p.id,
    p.display_name,
    p.age,
    p.gender_identity,
    p.interested_in,
    p.bio,
    p.city,
    p.is_verified,
    p.sexual_roles,
    p.verification_level,
    case
      when coalesce(my_loc.discovery_sharing, false)
        and my_loc.discovery_latitude is not null
        and my_loc.discovery_longitude is not null
        and coalesce(other_loc.discovery_sharing, false)
        and other_loc.discovery_latitude is not null
        and other_loc.discovery_longitude is not null
      then public.calculate_distance_km(
        my_loc.discovery_latitude,
        my_loc.discovery_longitude,
        other_loc.discovery_latitude,
        other_loc.discovery_longitude
      )
      else null
    end as distance_km
  from public.profiles p
  left join private.profile_locations my_loc on my_loc.user_id = auth.uid()
  left join private.profile_locations other_loc on other_loc.user_id = p.id
  where auth.uid() is not null
    and p.id <> auth.uid()
    and private.member_dating_community(auth.uid()) is not null
    and private.member_dating_community(p.id) =
        private.member_dating_community(auth.uid())
    and public.can_interact_with_member(p.id) is true
    and exists (
      select 1
      from public.profiles viewer
      where viewer.id = auth.uid()
        and private.match_preference_accepts_gender(viewer.interested_in, p.gender_identity)
        and private.match_preference_accepts_gender(p.interested_in, viewer.gender_identity)
        and private.member_meets_partner_preferences(viewer.id, p.id)
        and private.member_meets_partner_preferences(p.id, viewer.id)
    )
    and p.age is not null
    and p.age between greatest(18, coalesce(p_min_age, 18))
      and least(
        case
          when exists (
            select 1
            from public.premium_memberships membership
            where membership.user_id = auth.uid()
              and membership.premium_until > pg_catalog.now()
          ) then 99 else 79
        end,
        greatest(coalesce(p_min_age, 18), coalesce(p_max_age, 79))
      )
    and (
      nullif(btrim(coalesce(p_city, '')), '') is null
      or regexp_replace(lower(coalesce(p.city, '')), '[^a-z0-9]+', ' ', 'g')
         like '%' || regexp_replace(lower(btrim(p_city)), '[^a-z0-9]+', ' ', 'g') || '%'
    )
    and (
      not coalesce(my_loc.discovery_sharing, false)
      or my_loc.discovery_latitude is null
      or my_loc.discovery_longitude is null
      or not coalesce(other_loc.discovery_sharing, false)
      or other_loc.discovery_latitude is null
      or other_loc.discovery_longitude is null
      or public.calculate_distance_km(
        my_loc.discovery_latitude,
        my_loc.discovery_longitude,
        other_loc.discovery_latitude,
        other_loc.discovery_longitude
      ) <= greatest(1, least(coalesce(p_max_distance_km, 20050), 20050))
    );
$function$;

-- New likes must stay inside the derived lane and pass reciprocal gender
-- preference checks. Historical likes are not deleted or rewritten.
create or replace function private.enforce_same_dating_community_on_like()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_liker_lane text;
  v_liked_lane text;
  v_liker_gender text;
  v_liker_preference text;
  v_liked_gender text;
  v_liked_preference text;
begin
  v_liker_lane := private.member_dating_community(new.liker_id);
  v_liked_lane := private.member_dating_community(new.liked_id);

  if v_liker_lane is null or v_liked_lane is null then
    raise exception 'Complete your dating orientation before liking profiles.'
      using errcode = '23514';
  end if;

  if v_liker_lane <> v_liked_lane then
    raise exception 'You can only like members in your dating lane.'
      using errcode = '23514';
  end if;

  select gender_identity, interested_in
    into v_liker_gender, v_liker_preference
  from public.profiles
  where id = new.liker_id;

  select gender_identity, interested_in
    into v_liked_gender, v_liked_preference
  from public.profiles
  where id = new.liked_id;

  if not private.match_preference_accepts_gender(v_liker_preference, v_liked_gender)
     or not private.match_preference_accepts_gender(v_liked_preference, v_liker_gender) then
    raise exception 'This member does not meet both members'' dating preferences.'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

drop trigger if exists enforce_same_dating_community_on_like on public.likes;
create trigger enforce_same_dating_community_on_like
before insert or update of liker_id, liked_id on public.likes
for each row execute function private.enforce_same_dating_community_on_like();

revoke all on function private.enforce_same_dating_community_on_like()
  from public, anon, authenticated;

-- Passes are also restricted to the member's derived dating lane.
create or replace function private.enforce_same_dating_community_on_pass()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_passer_lane text;
  v_passed_lane text;
begin
  v_passer_lane := private.member_dating_community(new.passer_id);
  v_passed_lane := private.member_dating_community(new.passed_id);

  if v_passer_lane is null or v_passed_lane is null then
    raise exception 'Complete your dating orientation before passing profiles.'
      using errcode = '23514';
  end if;

  if v_passer_lane <> v_passed_lane then
    raise exception 'You can only pass members in your dating lane.'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

drop trigger if exists enforce_same_dating_community_on_pass on public.profile_passes;
create trigger enforce_same_dating_community_on_pass
before insert or update of passer_id, passed_id on public.profile_passes
for each row execute function private.enforce_same_dating_community_on_pass();

revoke all on function private.enforce_same_dating_community_on_pass()
  from public, anon, authenticated;

commit;

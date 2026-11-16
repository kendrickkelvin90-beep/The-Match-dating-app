-- Expand optional profile details with independent, explicit sharing consent.
-- Private values remain owner-only unless share_profile_extras is enabled.
begin;

alter table public.member_dating_details
  add column if not exists relationship_intention text not null default 'Still figuring it out',
  add column if not exists communication_style text not null default 'Prefer not to say',
  add column if not exists languages text[] not null default '{}'::text[],
  add column if not exists education_level text not null default 'Prefer not to say',
  add column if not exists occupation text not null default '',
  add column if not exists favorite_music text not null default '',
  add column if not exists favorite_movies text not null default '',
  add column if not exists favorite_food text not null default '',
  add column if not exists share_profile_extras boolean not null default false;

alter table public.member_dating_details
  add constraint member_dating_details_relationship_intention_check
    check (relationship_intention in ('Long-term relationship','Dating','Friendship','Casual dating','Still figuring it out','Prefer not to say')),
  add constraint member_dating_details_communication_style_check
    check (communication_style in ('Deep conversations','Humour and playful','Quality time','Acts of service','Texting','Phone or video calls','Prefer not to say')),
  add constraint member_dating_details_education_level_check
    check (education_level in ('Secondary school','Trade or professional training','Undergraduate','Graduate','Postgraduate','Prefer not to say')),
  add constraint member_dating_details_profile_text_lengths_check
    check (
      pg_catalog.char_length(occupation) <= 80
      and pg_catalog.char_length(favorite_music) <= 100
      and pg_catalog.char_length(favorite_movies) <= 100
      and pg_catalog.char_length(favorite_food) <= 100
    ),
  add constraint member_dating_details_languages_check
    check (
      pg_catalog.cardinality(languages) <= 8
      and not exists (
        select 1 from pg_catalog.unnest(languages) as language(value)
        where pg_catalog.char_length(pg_catalog.btrim(language.value)) < 2
           or pg_catalog.char_length(pg_catalog.btrim(language.value)) > 40
      )
    );

create or replace function public.get_shared_dating_details(p_user_ids uuid[])
returns table(
  user_id uuid,
  interests text[],
  smoking text,
  drinking text,
  activity_level text,
  pets text,
  children text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if coalesce(cardinality(p_user_ids), 0) > 100 then
    raise exception 'A maximum of 100 member IDs can be requested' using errcode = '22023';
  end if;

  return query
  with viewer_profile as (
    select viewer.id, viewer.gender_identity, viewer.interested_in
    from public.profiles viewer
    where viewer.id = auth.uid()
      and public.is_match_profile_complete(viewer.id)
      and (
        select pg_catalog.count(*)
        from public.profile_photos own_photo
        where own_photo.user_id = viewer.id
      ) >= 2
      and not exists (
        select 1
        from public.member_moderation own_moderation
        where own_moderation.user_id = viewer.id
          and (
            own_moderation.status = 'banned'
            or (
              own_moderation.status = 'suspended'
              and own_moderation.expires_at > pg_catalog.now()
            )
          )
      )
  ),
  visible_members as (
    select candidate.id
    from public.discover_profiles_secure(20050, 18, 99, null) visible
    join public.profiles candidate on candidate.id = visible.id
    cross join viewer_profile viewer
    where candidate.id = any(coalesce(p_user_ids, '{}'::uuid[]))
      and public.is_match_profile_complete(candidate.id)
      and (
        select pg_catalog.count(*)
        from public.profile_photos candidate_photo
        where candidate_photo.user_id = candidate.id
      ) >= 2
      and not exists (
        select 1
        from public.member_moderation candidate_moderation
        where candidate_moderation.user_id = candidate.id
          and (
            candidate_moderation.status = 'banned'
            or (
              candidate_moderation.status = 'suspended'
              and candidate_moderation.expires_at > pg_catalog.now()
            )
          )
      )
      and not exists (
        select 1
        from public.member_blocks block_record
        where (block_record.blocker_id = viewer.id and block_record.blocked_id = candidate.id)
           or (block_record.blocker_id = candidate.id and block_record.blocked_id = viewer.id)
      )
      and private.match_preference_accepts_gender(viewer.interested_in, candidate.gender_identity)
      and private.match_preference_accepts_gender(candidate.interested_in, viewer.gender_identity)
      and (
        coalesce((
          select viewer_onboarding.answers ->> 'sexual_orientation'
          from public.member_onboarding viewer_onboarding
          where viewer_onboarding.user_id = viewer.id
        ), '') <> 'Straight / heterosexual'
        or exists (
          select 1
          from public.member_onboarding candidate_onboarding
          where candidate_onboarding.user_id = candidate.id
            and candidate_onboarding.answers ->> 'sexual_orientation' = 'Straight / heterosexual'
        )
      )
  )
  select
    d.user_id,
    case when d.share_interests then d.interests else null end,
    case when d.share_lifestyle then d.smoking else null end,
    case when d.share_lifestyle then d.drinking else null end,
    case when d.share_lifestyle then d.activity_level else null end,
    case when d.share_lifestyle then d.pets else null end,
    case when d.share_lifestyle then d.children else null end
  from public.member_dating_details d
  join visible_members visible on visible.id = d.user_id
  where d.user_id = any(coalesce(p_user_ids, '{}'::uuid[]))
    and (d.share_interests or d.share_lifestyle or d.share_profile_extras);
end;
$function$;

create or replace function public.get_shared_profile_extras(p_user_ids uuid[])
returns table(
  user_id uuid,
  relationship_intention text,
  communication_style text,
  languages text[],
  education_level text,
  occupation text,
  favorite_music text,
  favorite_movies text,
  favorite_food text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if coalesce(cardinality(p_user_ids), 0) > 100 then
    raise exception 'A maximum of 100 member IDs can be requested' using errcode = '22023';
  end if;

  return query
  with currently_visible as (
    select shared.user_id
    from public.get_shared_dating_details(p_user_ids) shared
  )
  select d.user_id, d.relationship_intention, d.communication_style,
         d.languages, d.education_level, d.occupation,
         d.favorite_music, d.favorite_movies, d.favorite_food
  from public.member_dating_details d
  join currently_visible visible on visible.user_id = d.user_id
  where d.user_id = any(coalesce(p_user_ids, '{}'::uuid[]))
    and d.share_profile_extras;
end;
$function$;

revoke all on function public.get_shared_profile_extras(uuid[]) from public, anon;
grant execute on function public.get_shared_profile_extras(uuid[]) to authenticated;

comment on function public.get_shared_profile_extras(uuid[]) is
  'Returns optional dating profile details only for currently Discover-visible members who explicitly enabled profile-extra sharing.';

commit;

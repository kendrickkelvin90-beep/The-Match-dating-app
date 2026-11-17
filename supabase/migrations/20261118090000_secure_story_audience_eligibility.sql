-- Enforce Story "Everyone" audience through reciprocal Discover eligibility
-- and keep queer/straight audience groups separate. Mutual matches remain
-- explicitly allowed to see one another's "My Matches" Stories.

begin;

create or replace function private.can_view_story_from_owner(p_owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    auth.uid() is not null
    and p_owner_id is not null
    and p_owner_id <> auth.uid()
    and exists (
      select 1
      from public.profiles viewer
      join public.profiles owner on owner.id = p_owner_id
      join public.member_onboarding viewer_onboarding on viewer_onboarding.user_id = viewer.id
      join public.member_onboarding owner_onboarding on owner_onboarding.user_id = owner.id
      where viewer.id = auth.uid()
        and public.is_match_profile_complete(viewer.id)
        and public.is_match_profile_complete(owner.id)
        and viewer.age >= 18
        and owner.age >= 18
        and private.match_preference_accepts_gender(viewer.interested_in, owner.gender_identity)
        and private.match_preference_accepts_gender(owner.interested_in, viewer.gender_identity)
        and private.member_meets_partner_preferences(viewer.id, owner.id)
        and private.member_meets_partner_preferences(owner.id, viewer.id)
        and nullif(btrim(viewer_onboarding.answers ->> 'sexual_orientation'), '') is not null
        and nullif(btrim(owner_onboarding.answers ->> 'sexual_orientation'), '') is not null
        and (
          (viewer_onboarding.answers ->> 'sexual_orientation' = 'Straight / heterosexual'
           and owner_onboarding.answers ->> 'sexual_orientation' = 'Straight / heterosexual')
          or
          (viewer_onboarding.answers ->> 'sexual_orientation' <> 'Straight / heterosexual'
           and owner_onboarding.answers ->> 'sexual_orientation' <> 'Straight / heterosexual')
        )
        and (select count(*) from public.profile_photos viewer_photo where viewer_photo.user_id = viewer.id) >= 2
        and (select count(*) from public.profile_photos owner_photo where owner_photo.user_id = owner.id) >= 2
        and not exists (
          select 1 from public.member_blocks block_record
          where (block_record.blocker_id = viewer.id and block_record.blocked_id = owner.id)
             or (block_record.blocker_id = owner.id and block_record.blocked_id = viewer.id)
        )
        and not exists (
          select 1 from public.member_moderation moderation
          where moderation.user_id in (viewer.id, owner.id)
            and (
              moderation.status = 'banned'
              or (moderation.status = 'suspended' and moderation.expires_at > now())
            )
        )
    );
$function$;

revoke all on function private.can_view_story_from_owner(uuid) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.can_view_story_from_owner(uuid) to authenticated;

drop policy if exists "Members can view stories allowed by audience" on public.stories;
create policy "Members can view stories allowed by audience"
on public.stories
for select
to authenticated
using (
  expires_at > now()
  and (
    user_id = auth.uid()
    or (
      audience = 'everyone'
      and private.can_view_story_from_owner(user_id)
    )
    or (
      audience = 'matches'
      and public.can_interact_with_member(user_id)
      and public.are_users_mutual_matches(auth.uid(), user_id)
    )
  )
);

drop policy if exists "Members read permitted story media" on storage.objects;
create policy "Members read permitted story media"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'story-media'
  and exists (
    select 1
    from public.stories s
    where s.media_url = objects.name
      and s.expires_at > now()
      and (
        s.user_id = auth.uid()
        or (
          s.audience = 'everyone'
          and private.can_view_story_from_owner(s.user_id)
        )
        or (
          s.audience = 'matches'
          and public.can_interact_with_member(s.user_id)
          and public.are_users_mutual_matches(auth.uid(), s.user_id)
        )
      )
  )
);

comment on function private.can_view_story_from_owner(uuid) is
  'Allows Everyone-audience Story access only when the owner is in the viewer reciprocal Discover eligibility set and both members belong to the same straight/queer audience group.';

commit;

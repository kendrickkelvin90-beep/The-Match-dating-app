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
      from public.matchmaking_eligible_candidate_ids() eligible
      where eligible.user_id = p_owner_id
    )
    and exists (
      select 1
      from public.member_onboarding viewer_onboarding
      join public.member_onboarding owner_onboarding on true
      where viewer_onboarding.user_id = auth.uid()
        and owner_onboarding.user_id = p_owner_id
        and nullif(btrim(viewer_onboarding.answers ->> 'sexual_orientation'), '') is not null
        and nullif(btrim(owner_onboarding.answers ->> 'sexual_orientation'), '') is not null
        and (
          (viewer_onboarding.answers ->> 'sexual_orientation' = 'Straight / heterosexual'
           and owner_onboarding.answers ->> 'sexual_orientation' = 'Straight / heterosexual')
          or
          (viewer_onboarding.answers ->> 'sexual_orientation' <> 'Straight / heterosexual'
           and owner_onboarding.answers ->> 'sexual_orientation' <> 'Straight / heterosexual')
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

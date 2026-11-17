-- Member-controlled visibility in new Discover recommendations and optional public pronouns.
-- Existing matches and chats are not affected by Discover visibility.

begin;

alter table public.profiles
  add column if not exists pronouns text,
  add column if not exists discover_visibility text not null default 'everyone';

alter table public.profiles drop constraint if exists profiles_discover_visibility_check;
alter table public.profiles add constraint profiles_discover_visibility_check
  check (discover_visibility in ('everyone', 'matches_only'));

alter table public.profiles drop constraint if exists profiles_pronouns_check;
alter table public.profiles add constraint profiles_pronouns_check
  check (pronouns is null or pronouns in ('she/her','he/him','they/them','she/they','he/they','any pronouns','use my name'));

do $migration$
declare
  v_definition text;
  v_original text := 'and candidate.profile_paused = false';
  v_replacement text := 'and candidate.profile_paused = false
      and coalesce(candidate.discover_visibility, ''everyone'') = ''everyone''';
begin
  v_definition := pg_catalog.pg_get_functiondef(
    'public.matchmaking_eligible_candidate_ids(double precision,integer,integer,text,text,text[],boolean,text,integer)'::regprocedure
  );
  if pg_catalog.position(v_original in v_definition) = 0 then
    raise exception 'Expected server-side profile pause predicate was not found; refusing to alter matchmaking eligibility';
  end if;
  v_definition := pg_catalog.replace(v_definition, v_original, v_replacement);
  execute v_definition;
end
$migration$;

comment on column public.profiles.discover_visibility is
  'Controls inclusion in new Discover recommendations. matches_only excludes the member from new Discover recommendations while leaving existing matches and chats unchanged.';
comment on column public.profiles.pronouns is
  'Optional pronouns explicitly chosen by the member for display on their public profile.';

commit;

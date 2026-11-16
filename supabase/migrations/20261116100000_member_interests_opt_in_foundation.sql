-- Optional member-controlled interests.
-- No existing profile fields or member records are changed.
-- Interest selections remain private to their owner until a separate,
-- privacy-reviewed, consent-gated matching read path is approved.

begin;

create table public.interest_catalog (
  code text primary key
    check (code ~ '^[a-z][a-z0-9_]{1,39}$'),
  label text not null
    check (char_length(btrim(label)) between 2 and 50),
  category text not null
    check (category in (
      'arts', 'food', 'outdoors', 'sports',
      'culture', 'technology', 'community', 'lifestyle'
    )),
  is_active boolean not null default true,
  sort_order smallint not null default 0
);

insert into public.interest_catalog (code, label, category, sort_order) values
  ('music', 'Music', 'culture', 10),
  ('movies', 'Movies', 'culture', 20),
  ('reading', 'Reading', 'arts', 30),
  ('photography', 'Photography', 'arts', 40),
  ('art_and_design', 'Art and design', 'arts', 50),
  ('writing', 'Writing', 'arts', 60),
  ('dancing', 'Dancing', 'arts', 70),
  ('theatre', 'Theatre', 'arts', 80),
  ('cooking', 'Cooking', 'food', 90),
  ('coffee', 'Coffee', 'food', 100),
  ('trying_new_food', 'Trying new food', 'food', 110),
  ('travel', 'Travel', 'outdoors', 120),
  ('hiking', 'Hiking', 'outdoors', 130),
  ('beach_days', 'Beach days', 'outdoors', 140),
  ('nature', 'Nature', 'outdoors', 150),
  ('fitness', 'Fitness', 'lifestyle', 160),
  ('football', 'Football', 'sports', 170),
  ('basketball', 'Basketball', 'sports', 180),
  ('swimming', 'Swimming', 'sports', 190),
  ('gaming', 'Gaming', 'technology', 200),
  ('technology', 'Technology', 'technology', 210),
  ('podcasts', 'Podcasts', 'culture', 220),
  ('board_games', 'Board games', 'lifestyle', 230),
  ('language_learning', 'Language learning', 'culture', 240),
  ('pets', 'Pets', 'lifestyle', 250),
  ('gardening', 'Gardening', 'lifestyle', 260),
  ('volunteering', 'Volunteering', 'community', 270),
  ('community_events', 'Community events', 'community', 280),
  ('entrepreneurship', 'Entrepreneurship', 'technology', 290),
  ('fashion', 'Fashion', 'lifestyle', 300);

create table public.member_interest_sharing (
  user_id uuid primary key references auth.users(id) on delete cascade,
  share_for_matching boolean not null default false,
  consent_version text,
  consented_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint member_interest_sharing_consent_consistent check (
    (share_for_matching and consent_version is not null and consented_at is not null)
    or
    (not share_for_matching and consent_version is null and consented_at is null)
  )
);

create table public.member_interests (
  user_id uuid not null references auth.users(id) on delete cascade,
  interest_code text not null references public.interest_catalog(code) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (user_id, interest_code)
);

comment on table public.interest_catalog is
  'Curated, non-sensitive interest labels available for optional matchmaking.';
comment on table public.member_interest_sharing is
  'Per-member opt-in for using their selected interests in compatibility ranking. Missing row means opted out.';
comment on table public.member_interests is
  'Private member-owned interest selections. Other members cannot read this table directly.';

alter table public.interest_catalog enable row level security;
alter table public.member_interest_sharing enable row level security;
alter table public.member_interests enable row level security;

revoke all on table public.interest_catalog from anon, authenticated;
revoke all on table public.member_interest_sharing from anon, authenticated;
revoke all on table public.member_interests from anon, authenticated;

grant select on table public.interest_catalog to authenticated;
grant select, insert, update, delete on table public.member_interest_sharing to authenticated;
grant select, insert, delete on table public.member_interests to authenticated;

create policy "Signed-in members can view active interest choices"
  on public.interest_catalog
  for select
  to authenticated
  using (is_active);

create policy "Members manage their own interest sharing choice"
  on public.member_interest_sharing
  for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Members manage only their own interests"
  on public.member_interests
  for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function private.prepare_member_interest_sharing()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.share_for_matching then
    if tg_op = 'INSERT' or not old.share_for_matching then
      new.consent_version := 'v1';
      new.consented_at := pg_catalog.now();
    else
      new.consent_version := old.consent_version;
      new.consented_at := old.consented_at;
    end if;
  else
    new.consent_version := null;
    new.consented_at := null;
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

revoke all on function private.prepare_member_interest_sharing() from public, anon, authenticated;

create trigger prepare_member_interest_sharing
  before insert or update on public.member_interest_sharing
  for each row execute function private.prepare_member_interest_sharing();

create or replace function private.validate_member_interest_insert()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  current_count integer;
begin
  if not exists (
    select 1
    from public.interest_catalog catalog
    where catalog.code = new.interest_code
      and catalog.is_active
  ) then
    raise exception 'Interest choice is not available'
      using errcode = 'check_violation';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.user_id::text, 0)
  );

  select count(*)::integer
    into current_count
  from public.member_interests existing
  where existing.user_id = new.user_id;

  if current_count >= 20 then
    raise exception 'A member can select no more than 20 interests'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$function$;

revoke all on function private.validate_member_interest_insert() from public, anon, authenticated;

create trigger validate_member_interest_insert
  before insert on public.member_interests
  for each row execute function private.validate_member_interest_insert();

commit;

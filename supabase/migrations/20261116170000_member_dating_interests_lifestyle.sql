-- Private member lifestyle and interest details with explicit sharing controls.
-- These values are optional, owner-managed, and never exposed through profiles directly.

begin;

create table if not exists public.member_dating_details (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  interests text[] not null default '{}'::text[],
  smoking text not null default 'Prefer not to say'
    check (smoking in ('Never','Occasionally','Socially','Regularly','Prefer not to say')),
  drinking text not null default 'Prefer not to say'
    check (drinking in ('Never','Occasionally','Socially','Regularly','Prefer not to say')),
  activity_level text not null default 'Prefer not to say'
    check (activity_level in ('Very active','Moderately active','Not very active','Prefer not to say')),
  pets text not null default 'Prefer not to say'
    check (pets in ('Have pets','Love pets','Want pets','Not for me','Prefer not to say')),
  children text not null default 'Prefer not to say'
    check (children in ('Have children','Want children','Do not want children','Not sure','Prefer not to say')),
  share_interests boolean not null default false,
  share_lifestyle boolean not null default false,
  updated_at timestamptz not null default pg_catalog.now()
);

alter table public.member_dating_details enable row level security;
revoke all on public.member_dating_details from public, anon;
grant select, insert, update, delete on public.member_dating_details to authenticated;

drop policy if exists "Members manage own dating details" on public.member_dating_details;
create policy "Members manage own dating details"
  on public.member_dating_details
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function private.validate_member_dating_details()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  allowed_interests text[] := array[
    'Music','Movies & TV','Travel','Food & cooking','Fitness','Gym',
    'Football','Basketball','Gaming','Reading','Art & design','Photography',
    'Fashion','Nature & hiking','Dancing','Nightlife','Volunteering',
    'Technology','Business','Spirituality','Pets','Beach & outdoors',
    'Comedy','Podcasts','Cars','Board games','Live events','Gardening',
    'Running','Swimming','Cycling','Yoga','Volleyball','Tennis','Badminton',
    'Boxing & martial arts','Cooking & baking','Street food','Cafés',
    'Concerts & festivals','Anime & manga','Writing & poetry','Languages',
    'Camping','Road trips','Fashion & beauty','Home decor','DIY & crafts',
    'History & museums','Startups & entrepreneurship'
  ];
begin
  if coalesce(cardinality(new.interests), 0) > 10 then
    raise exception 'Choose no more than 10 interests' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(coalesce(new.interests, '{}'::text[])) as interests(value)
    where not (value = any(allowed_interests))
  ) then
    raise exception 'One or more interests are not supported' using errcode = '22023';
  end if;
  if coalesce(cardinality(new.interests), 0) <>
     (select count(distinct value) from unnest(coalesce(new.interests, '{}'::text[])) as interests(value)) then
    raise exception 'Interests cannot contain duplicates' using errcode = '22023';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

drop trigger if exists validate_member_dating_details on public.member_dating_details;
create trigger validate_member_dating_details
  before insert or update on public.member_dating_details
  for each row execute function private.validate_member_dating_details();

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
  with visible_members as (
    select visible.id
    from public.discover_profiles_secure(20050, 18, 99, null) visible
    where visible.id = any(coalesce(p_user_ids, '{}'::uuid[]))
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
    and (d.share_interests or d.share_lifestyle);
end;
$function$;

revoke all on function public.get_shared_dating_details(uuid[]) from public, anon;
grant execute on function public.get_shared_dating_details(uuid[]) to authenticated;

comment on table public.member_dating_details is
  'Optional owner-managed interests and lifestyle details. Direct reads are owner-only; shared values are returned through get_shared_dating_details only when the member opts in.';
comment on function public.get_shared_dating_details(uuid[]) is
  'Returns only the interest and lifestyle fields each member explicitly opted to share.';

commit;

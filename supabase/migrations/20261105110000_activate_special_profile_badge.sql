-- Allow members to activate an owned Special Profile Badge and display only active badges publicly.
create table if not exists public.member_profile_badges (
  user_id uuid primary key references auth.users(id) on delete cascade,
  activated_at timestamptz not null default now()
);
alter table public.member_profile_badges enable row level security;
revoke all on public.member_profile_badges from anon, authenticated;
grant select on public.member_profile_badges to authenticated;
drop policy if exists member_profile_badges_active_read on public.member_profile_badges;
create policy member_profile_badges_active_read
  on public.member_profile_badges for select to authenticated
  using (true);

create or replace function public.set_my_profile_badge_active(p_active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_owned integer;
begin
  if v_uid is null then raise exception 'Please sign in to manage your profile badge.'; end if;
  if p_active is null then raise exception 'Choose whether to activate or deactivate your badge.'; end if;
  if p_active then
    select coalesce(quantity,0) into v_owned
    from public.coin_store_inventory
    where user_id=v_uid and item_code='decorative_badge';
    if coalesce(v_owned,0)<1 then
      raise exception 'You need to own a Special Profile Badge before activating it.';
    end if;
    insert into public.member_profile_badges(user_id,activated_at)
    values(v_uid,now())
    on conflict(user_id) do update set activated_at=excluded.activated_at;
  else
    delete from public.member_profile_badges where user_id=v_uid;
  end if;
  return p_active;
end;
$$;
revoke all on function public.set_my_profile_badge_active(boolean) from public,anon;
grant execute on function public.set_my_profile_badge_active(boolean) to authenticated;

create or replace function public.get_active_profile_badge_ids(p_user_ids uuid[])
returns table(user_id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select b.user_id
  from public.member_profile_badges b
  where b.user_id = any(coalesce(p_user_ids, array[]::uuid[]))
  limit 100;
$$;
revoke all on function public.get_active_profile_badge_ids(uuid[]) from public,anon;
grant execute on function public.get_active_profile_badge_ids(uuid[]) to authenticated;

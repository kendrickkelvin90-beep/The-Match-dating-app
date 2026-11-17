-- Let members control whether their live online presence is visible.
-- Existing members retain the current behavior by default.
begin;
alter table public.profiles
  add column if not exists show_online_status boolean not null default true;
comment on column public.profiles.show_online_status is
  'When false, the member does not publish live Realtime online presence to other members.';
commit;

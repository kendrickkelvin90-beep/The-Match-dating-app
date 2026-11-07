create table if not exists public.deleted_account_device_blocks (
  device_hash text primary key,
  created_at timestamptz not null default now(),
  source text not null default 'self_service_account_deletion'
);

alter table public.deleted_account_device_blocks enable row level security;
revoke all on table public.deleted_account_device_blocks from anon, authenticated;
grant all on table public.deleted_account_device_blocks to service_role;

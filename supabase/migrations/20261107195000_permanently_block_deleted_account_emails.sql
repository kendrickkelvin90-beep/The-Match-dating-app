create table if not exists public.deleted_account_email_blocks (
  email_hash text primary key
    check (email_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  source text not null default 'self_service_account_deletion'
);

comment on table public.deleted_account_email_blocks is
  'Private anti-re-registration tombstones. Stores only normalized SHA-256 email hashes, not profile or credential data.';

alter table public.deleted_account_email_blocks enable row level security;

revoke all on table public.deleted_account_email_blocks from public, anon, authenticated;
grant select, insert, delete on table public.deleted_account_email_blocks to service_role;

insert into public.deleted_account_email_blocks (email_hash, source)
values
  (encode(extensions.digest(lower(btrim('kosokowarisabayomi66@gmail.com')), 'sha256'), 'hex'), 'previously_deleted_account'),
  (encode(extensions.digest(lower(btrim('heisdaves001@gmail.com')), 'sha256'), 'hex'), 'previously_deleted_account'),
  (encode(extensions.digest(lower(btrim('sodiqlawal2168@gmail.com')), 'sha256'), 'hex'), 'previously_deleted_account')
on conflict (email_hash) do nothing;

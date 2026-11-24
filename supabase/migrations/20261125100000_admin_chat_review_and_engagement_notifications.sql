-- Admin-only chat review with an immutable access trail.
-- Messages remain private to their two participants; administrators access them only
-- through this audited RPC. This is not end-to-end encryption.
begin;

create table if not exists public.admin_chat_review_audit (
  id bigint generated always as identity primary key,
  admin_user_id uuid not null references auth.users(id) on delete restrict,
  search_term text,
  requested_limit integer not null check (requested_limit between 1 and 100),
  accessed_at timestamptz not null default now()
);

create index if not exists admin_chat_review_audit_accessed_at_idx
  on public.admin_chat_review_audit(accessed_at desc);
alter table public.admin_chat_review_audit enable row level security;
revoke all on public.admin_chat_review_audit from public, anon, authenticated;
grant select on public.admin_chat_review_audit to authenticated;
drop policy if exists admin_chat_review_audit_admin_read on public.admin_chat_review_audit;
create policy admin_chat_review_audit_admin_read
  on public.admin_chat_review_audit for select to authenticated
  using (public.is_match_admin());

create or replace function public.admin_list_chat_messages(
  p_search text default null,
  p_before timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 50
)
returns table(
  message_id uuid,
  sender_id uuid,
  sender_name text,
  receiver_id uuid,
  receiver_name text,
  message_body text,
  created_at timestamptz,
  read_at timestamptz,
  unsent_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin uuid := auth.uid();
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
begin
  if v_admin is null or not public.is_match_admin() then
    raise exception 'Administrator access required.' using errcode = '42501';
  end if;

  insert into public.admin_chat_review_audit(admin_user_id, search_term, requested_limit)
  values (v_admin, left(v_search, 200), v_limit);

  return query
  select m.id, m.sender_id,
         coalesce(nullif(btrim(sender.display_name), ''), 'Member'),
         m.receiver_id,
         coalesce(nullif(btrim(receiver.display_name), ''), 'Member'),
         case when m.unsent_at is not null then '[Message unsent]' else m.body end,
         m.created_at, m.read_at, m.unsent_at
  from public.messages m
  left join public.profiles sender on sender.id = m.sender_id
  left join public.profiles receiver on receiver.id = m.receiver_id
  where (p_before is null or m.created_at < p_before)
    and (
      v_search is null
      or m.body ilike '%' || v_search || '%'
      or m.sender_id::text ilike '%' || v_search || '%'
      or m.receiver_id::text ilike '%' || v_search || '%'
      or sender.display_name ilike '%' || v_search || '%'
      or receiver.display_name ilike '%' || v_search || '%'
    )
  order by m.created_at desc, m.id desc
  limit v_limit;
end;
$function$;

revoke all on function public.admin_list_chat_messages(text,timestamptz,uuid,integer)
  from public, anon;
grant execute on function public.admin_list_chat_messages(text,timestamptz,uuid,integer)
  to authenticated;

comment on table public.admin_chat_review_audit is
  'Audit trail of administrator access to private member chat messages.';
commit;

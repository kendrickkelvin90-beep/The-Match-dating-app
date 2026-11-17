-- Secure message replies and reactions. Reactions are one per member/message;
-- changing an emoji replaces the previous reaction, and tapping it again removes it.
alter table public.messages
  add column if not exists reply_to_message_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.messages'::regclass
      and conname = 'messages_reply_to_message_id_fkey'
  ) then
    alter table public.messages
      add constraint messages_reply_to_message_id_fkey
      foreign key (reply_to_message_id)
      references public.messages(id)
      on delete set null;
  end if;
end;
$$;

create index if not exists messages_reply_to_message_id_idx
  on public.messages(reply_to_message_id)
  where reply_to_message_id is not null;

create or replace function public.validate_chat_message_reply()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.messages%rowtype;
begin
  if new.reply_to_message_id is null then
    return new;
  end if;

  if new.reply_to_message_id = new.id then
    raise exception 'A message cannot reply to itself';
  end if;

  select * into v_target
  from public.messages
  where id = new.reply_to_message_id;

  if not found
     or v_target.unsent_at is not null
     or not (
       (v_target.sender_id = new.sender_id and v_target.receiver_id = new.receiver_id)
       or
       (v_target.sender_id = new.receiver_id and v_target.receiver_id = new.sender_id)
     ) then
    raise exception 'The reply target is not available in this conversation';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_chat_message_reply on public.messages;
create trigger validate_chat_message_reply
before insert or update of reply_to_message_id, sender_id, receiver_id
on public.messages
for each row execute function public.validate_chat_message_reply();

create table if not exists public.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (emoji in ('❤️','😂','😍','😮','😢','👍')),
  created_at timestamptz not null default now(),
  constraint message_reactions_one_per_member unique(message_id, user_id)
);

create index if not exists message_reactions_message_idx
  on public.message_reactions(message_id, created_at);

alter table public.message_reactions enable row level security;
revoke all on public.message_reactions from public, anon, authenticated;
grant select on public.message_reactions to authenticated;

drop policy if exists message_reactions_conversation_read on public.message_reactions;
create policy message_reactions_conversation_read
on public.message_reactions for select to authenticated
using (
  exists (
    select 1 from public.messages m
    where m.id = message_reactions.message_id
      and auth.uid() in (m.sender_id, m.receiver_id)
      and public.can_interact_with_member(
        case when m.sender_id = auth.uid() then m.receiver_id else m.sender_id end
      )
  )
);

create or replace function public.toggle_chat_message_reaction(
  p_message_id uuid,
  p_emoji text
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_message public.messages%rowtype;
  v_existing text;
begin
  if v_user is null then raise exception 'Please sign in.'; end if;
  if p_emoji not in ('❤️','😂','😍','😮','😢','👍') then
    raise exception 'Choose a supported reaction.';
  end if;

  select * into v_message
  from public.messages
  where id = p_message_id
    and v_user in (sender_id, receiver_id)
  for share;

  if not found or v_message.unsent_at is not null then
    raise exception 'This message is no longer available.';
  end if;

  if not public.can_interact_with_member(
    case when v_message.sender_id = v_user
      then v_message.receiver_id else v_message.sender_id end
  ) then
    raise exception 'This conversation is unavailable.';
  end if;

  select emoji into v_existing
  from public.message_reactions
  where message_id = p_message_id and user_id = v_user
  for update;

  if v_existing = p_emoji then
    delete from public.message_reactions
    where message_id = p_message_id and user_id = v_user;
    return false;
  end if;

  insert into public.message_reactions(message_id, user_id, emoji)
  values (p_message_id, v_user, p_emoji)
  on conflict (message_id, user_id)
  do update set emoji = excluded.emoji, created_at = now();

  return true;
end;
$$;

revoke all on function public.toggle_chat_message_reaction(uuid,text) from public, anon;
grant execute on function public.toggle_chat_message_reaction(uuid,text) to authenticated;

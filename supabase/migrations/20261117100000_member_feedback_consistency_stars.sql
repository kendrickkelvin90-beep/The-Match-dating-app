-- The Match member experience feedback and Consistency Stars.
-- Review and test this migration in staging before applying to production.

create table if not exists public.member_consistency (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak_days integer not null default 0 check (current_streak_days >= 0),
  total_active_days integer not null default 0 check (total_active_days >= 0),
  active_days_in_cycle integer not null default 0 check (active_days_in_cycle between 0 and 34),
  stars_progress integer not null default 0 check (stars_progress between 0 and 4),
  rewards_claimed integer not null default 0 check (rewards_claimed >= 0),
  last_active_date date,
  updated_at timestamptz not null default now()
);

create table if not exists public.member_consistency_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_date date not null,
  created_at timestamptz not null default now(),
  primary key(user_id, activity_date)
);

create table if not exists public.member_experience_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  statement_key text not null check (statement_key in (
    'safety','respect','connections','ease_of_use','recommendation'
  )),
  rating smallint not null check (rating between 1 and 5),
  created_at timestamptz not null default now(),
  unique(user_id, statement_key)
);

create table if not exists public.member_feedback_prompt_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  next_prompt_at timestamptz not null default now(),
  last_prompt_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.member_consistency enable row level security;
alter table public.member_consistency_days enable row level security;
alter table public.member_experience_feedback enable row level security;
alter table public.member_feedback_prompt_state enable row level security;

drop policy if exists member_consistency_owner_read on public.member_consistency;
create policy member_consistency_owner_read on public.member_consistency
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists member_consistency_days_owner_read on public.member_consistency_days;
create policy member_consistency_days_owner_read on public.member_consistency_days
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists member_experience_feedback_admin_read on public.member_experience_feedback;
create policy member_experience_feedback_admin_read on public.member_experience_feedback
  for select to authenticated using (
    exists(select 1 from public.app_admins a where a.user_id = (select auth.uid()))
  );

revoke all on public.member_consistency, public.member_consistency_days,
  public.member_experience_feedback, public.member_feedback_prompt_state
  from anon, authenticated;
grant select on public.member_consistency, public.member_consistency_days to authenticated;
grant select on public.member_experience_feedback to authenticated;

-- A consistency reward uses the existing append-only wallet ledger.
alter table public.coin_ledger drop constraint if exists coin_ledger_entry_type_check;
alter table public.coin_ledger add constraint coin_ledger_entry_type_check
  check (entry_type in (
    'purchase_credit','store_debit','membership_debit','annual_bonus',
    'admin_adjustment','reversal','gift_send','gift_redeem','consistency_reward'
  ));

create or replace function public.match_record_daily_activity()
returns table(
  current_streak_days integer,
  total_active_days integer,
  active_days_in_cycle integer,
  stars_progress integer,
  rewards_claimed integer,
  reward_coins integer,
  already_checked_in boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Africa/Lagos')::date;
  v_last date;
  v_streak integer;
  v_total integer;
  v_cycle integer;
  v_stars integer;
  v_rewards integer;
  v_balance integer;
  v_reward integer := 0;
  v_inserted integer;
  v_key text;
begin
  if v_uid is null then raise exception 'Sign in to record your activity.'; end if;

  insert into public.member_consistency(user_id)
  values(v_uid) on conflict(user_id) do nothing;

  select m.last_active_date, m.current_streak_days, m.total_active_days,
         m.active_days_in_cycle, m.stars_progress, m.rewards_claimed
    into v_last, v_streak, v_total, v_cycle, v_stars, v_rewards
    from public.member_consistency m
   where m.user_id=v_uid for update;

  insert into public.member_consistency_days(user_id,activity_date)
  values(v_uid,v_today) on conflict(user_id,activity_date) do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted=0 then
    return query select v_streak,v_total,v_cycle,v_stars,v_rewards,0,true;
    return;
  end if;

  if v_last=v_today-1 then
    v_streak:=v_streak+1;
  else
    v_streak:=1;
  end if;

  v_total:=v_total+1;
  v_cycle:=v_cycle+1;

  if v_cycle % 7 = 0 then
    v_stars:=least(4,v_cycle/7);
  end if;

  if v_cycle>=35 then
    v_reward:=100;
    v_rewards:=v_rewards+1;
    v_cycle:=0;
    v_stars:=0;

    insert into public.coin_wallets(user_id) values(v_uid)
    on conflict(user_id) do nothing;
    select w.balance into v_balance from public.coin_wallets w
     where w.user_id=v_uid for update;
    update public.coin_wallets
       set balance=balance+v_reward, updated_at=now()
     where user_id=v_uid returning balance into v_balance;

    v_key:='consistency-stars:'||v_uid::text||':'||v_rewards::text;
    insert into public.coin_ledger(
      user_id,amount,balance_after,entry_type,idempotency_key,description
    ) values(
      v_uid,v_reward,v_balance,'consistency_reward',v_key,
      'Consistency Stars reward — completed five stars'
    );
  end if;

  update public.member_consistency
     set current_streak_days=v_streak,
         total_active_days=v_total,
         active_days_in_cycle=v_cycle,
         stars_progress=v_stars,
         rewards_claimed=v_rewards,
         last_active_date=v_today,
         updated_at=now()
   where user_id=v_uid;

  return query select v_streak,v_total,v_cycle,v_stars,v_rewards,v_reward,false;
end;
$$;
revoke all on function public.match_record_daily_activity() from public, anon;
grant execute on function public.match_record_daily_activity() to authenticated;

create or replace function public.match_get_experience_prompt()
returns table(statement_key text, statement_text text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_total integer;
  v_next timestamptz;
begin
  if v_uid is null then return; end if;

  select total_active_days into v_total
    from public.member_consistency where user_id=v_uid;
  if coalesce(v_total,0)<7 then return; end if;

  insert into public.member_feedback_prompt_state(user_id)
  values(v_uid) on conflict(user_id) do nothing;

  select next_prompt_at into v_next
    from public.member_feedback_prompt_state
   where user_id=v_uid for update;
  if v_next>now() then return; end if;

  return query
  select q.key,q.question
    from (values
      (1,'safety','I feel safe being myself on The Match.'),
      (2,'respect','Members treat me with respect.'),
      (3,'connections','I find people I am genuinely interested in.'),
      (4,'ease_of_use','The Match is easy to use.'),
      (5,'recommendation','I would recommend The Match to a friend.')
    ) as q(sort_order,key,question)
   where not exists(
     select 1 from public.member_experience_feedback f
      where f.user_id=v_uid and f.statement_key=q.key
   )
   order by q.sort_order
   limit 1;

  if found then
    update public.member_feedback_prompt_state
       set last_prompt_at=now(), next_prompt_at=now()+interval '30 days',
           updated_at=now()
     where user_id=v_uid;
  end if;
end;
$$;
revoke all on function public.match_get_experience_prompt() from public, anon;
grant execute on function public.match_get_experience_prompt() to authenticated;

create or replace function public.match_submit_experience_rating(
  p_statement_key text, p_rating integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Sign in to submit feedback.'; end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'Choose a rating from one to five stars.';
  end if;
  if p_statement_key not in ('safety','respect','connections','ease_of_use','recommendation') then
    raise exception 'Invalid feedback question.';
  end if;
  insert into public.member_experience_feedback(user_id,statement_key,rating)
  values(v_uid,p_statement_key,p_rating)
  on conflict(user_id,statement_key) do nothing;
  if not found then raise exception 'You have already answered this question.'; end if;
  insert into public.member_feedback_prompt_state(user_id,next_prompt_at,updated_at)
  values(v_uid,now()+interval '30 days',now())
  on conflict(user_id) do update set
    next_prompt_at=now()+interval '30 days',updated_at=now();
  return true;
end;
$$;
revoke all on function public.match_submit_experience_rating(text,integer) from public, anon;
grant execute on function public.match_submit_experience_rating(text,integer) to authenticated;

create or replace function public.match_dismiss_experience_prompt()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then return; end if;
  insert into public.member_feedback_prompt_state(user_id,next_prompt_at,updated_at)
  values(v_uid,now()+interval '30 days',now())
  on conflict(user_id) do update set
    next_prompt_at=now()+interval '30 days',updated_at=now();
end;
$$;
revoke all on function public.match_dismiss_experience_prompt() from public, anon;
grant execute on function public.match_dismiss_experience_prompt() to authenticated;

comment on table public.member_consistency is
  'Private member activity streak and five-star consistency reward progress.';
comment on table public.member_experience_feedback is
  'Private one-time-per-question member experience ratings; visible only to app admins.';

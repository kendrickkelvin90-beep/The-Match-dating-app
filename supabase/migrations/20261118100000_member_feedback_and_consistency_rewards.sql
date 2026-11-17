-- Member experience feedback and five-day consistency rewards.
-- Rewards are granted server-side and are idempotent per member/day.

create table if not exists public.match_consistency_streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak integer not null default 0 check (current_streak >= 0),
  longest_streak integer not null default 0 check (longest_streak >= 0),
  total_active_days integer not null default 0 check (total_active_days >= 0),
  star_progress integer not null default 0 check (star_progress between 0 and 4),
  total_rewards integer not null default 0 check (total_rewards >= 0),
  last_checkin_on date,
  last_reward_date date,
  updated_at timestamptz not null default now()
);

alter table public.match_consistency_streaks enable row level security;
drop policy if exists match_consistency_owner_read on public.match_consistency_streaks;
create policy match_consistency_owner_read
  on public.match_consistency_streaks for select to authenticated
  using (user_id = (select auth.uid()));
revoke all on public.match_consistency_streaks from anon, authenticated;
grant select on public.match_consistency_streaks to authenticated;

-- Add a dedicated, auditable ledger type for consistency rewards.
alter table public.coin_ledger drop constraint if exists coin_ledger_entry_type_check;
alter table public.coin_ledger
  add constraint coin_ledger_entry_type_check
  check (entry_type in (
    'purchase_credit','store_debit','membership_debit','annual_bonus',
    'admin_adjustment','reversal','consistency_reward'
  ));

create or replace function public.match_consistency_checkin()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Africa/Lagos')::date;
  v_state public.match_consistency_streaks%rowtype;
  v_streak integer;
  v_longest integer;
  v_total integer;
  v_progress integer;
  v_rewards integer;
  v_reward boolean := false;
  v_balance integer;
  v_reward_coins integer := 25;
begin
  if v_uid is null then raise exception 'Sign in to earn consistency stars'; end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text, 5105));
  select * into v_state
    from public.match_consistency_streaks
    where user_id = v_uid
    for update;

  if found and v_state.last_checkin_on = v_today then
    return jsonb_build_object(
      'current_streak', v_state.current_streak,
      'longest_streak', v_state.longest_streak,
      'total_active_days', v_state.total_active_days,
      'stars_progress', case when v_state.last_reward_date = v_today then 5 else v_state.star_progress end,
      'total_rewards', v_state.total_rewards,
      'reward_earned', false,
      'reward_coins', 0,
      'already_checked_in', true
    );
  end if;

  if not found then
    v_streak := 1;
    v_longest := 1;
    v_total := 1;
    v_rewards := 0;
  else
    v_streak := case
      when v_state.last_checkin_on = v_today - 1 then v_state.current_streak + 1
      else 1
    end;
    v_longest := greatest(v_state.longest_streak, v_streak);
    v_total := v_state.total_active_days + 1;
    v_rewards := v_state.total_rewards;
  end if;

  v_progress := mod(v_streak, 5);
  if v_progress = 0 then
    v_reward := true;
    v_rewards := v_rewards + 1;
    insert into public.coin_wallets(user_id) values (v_uid)
      on conflict (user_id) do nothing;
    select balance into v_balance
      from public.coin_wallets where user_id = v_uid for update;
    update public.coin_wallets
      set balance = balance + v_reward_coins, updated_at = now()
      where user_id = v_uid
      returning balance into v_balance;
    insert into public.coin_ledger(
      user_id, amount, balance_after, entry_type, idempotency_key, description
    ) values (
      v_uid, v_reward_coins, v_balance, 'consistency_reward',
      'consistency-reward:' || v_today::text,
      'Five consecutive active days consistency reward'
    );
  end if;

  insert into public.match_consistency_streaks(
    user_id, current_streak, longest_streak, total_active_days,
    star_progress, total_rewards, last_checkin_on, last_reward_date, updated_at
  ) values (
    v_uid, v_streak, v_longest, v_total,
    case when v_reward then 0 else v_progress end,
    v_rewards, v_today, case when v_reward then v_today else v_state.last_reward_date end, now()
  )
  on conflict (user_id) do update set
    current_streak = excluded.current_streak,
    longest_streak = excluded.longest_streak,
    total_active_days = excluded.total_active_days,
    star_progress = excluded.star_progress,
    total_rewards = excluded.total_rewards,
    last_checkin_on = excluded.last_checkin_on,
    last_reward_date = excluded.last_reward_date,
    updated_at = now();

  return jsonb_build_object(
    'current_streak', v_streak,
    'longest_streak', v_longest,
    'total_active_days', v_total,
    'stars_progress', case when v_reward then 5 else v_progress end,
    'total_rewards', v_rewards,
    'reward_earned', v_reward,
    'reward_coins', case when v_reward then v_reward_coins else 0 end,
    'already_checked_in', false
  );
end;
$$;

revoke all on function public.match_consistency_checkin() from public, anon;
grant execute on function public.match_consistency_checkin() to authenticated;

create table if not exists public.match_experience_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  statement_key text not null check (statement_key in (
    'safety','respect','connections','ease','recommend'
  )),
  rating integer not null check (rating between 1 and 5),
  created_at timestamptz not null default now()
);
create index if not exists match_experience_feedback_created_idx
  on public.match_experience_feedback(created_at desc);

create table if not exists public.match_feedback_prompt_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  dismissed_until timestamptz,
  last_submitted_at timestamptz,
  survey_count integer not null default 0 check (survey_count >= 0),
  updated_at timestamptz not null default now()
);

alter table public.match_experience_feedback enable row level security;
alter table public.match_feedback_prompt_state enable row level security;
drop policy if exists match_experience_feedback_owner_read on public.match_experience_feedback;
create policy match_experience_feedback_owner_read
  on public.match_experience_feedback for select to authenticated
  using (user_id = (select auth.uid()));
revoke all on public.match_experience_feedback, public.match_feedback_prompt_state from anon, authenticated;
grant select on public.match_experience_feedback to authenticated;

create or replace function public.match_get_experience_prompt()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_streak integer;
  v_state public.match_feedback_prompt_state%rowtype;
  v_key text;
begin
  if v_uid is null then return null; end if;
  select current_streak into v_streak
    from public.match_consistency_streaks where user_id = v_uid;
  if coalesce(v_streak, 0) < 7 then return null; end if;

  select * into v_state from public.match_feedback_prompt_state
    where user_id = v_uid;
  if found then
    if v_state.dismissed_until is not null and v_state.dismissed_until > now() then return null; end if;
    if v_state.last_submitted_at is not null and v_state.last_submitted_at > now() - interval '180 days' then return null; end if;
  end if;

  v_key := case mod(coalesce(v_state.survey_count, 0), 5)
    when 0 then 'safety'
    when 1 then 'respect'
    when 2 then 'connections'
    when 3 then 'ease'
    else 'recommend'
  end;
  return jsonb_build_object('statement_key', v_key);
end;
$$;
revoke all on function public.match_get_experience_prompt() from public, anon;
grant execute on function public.match_get_experience_prompt() to authenticated;

create or replace function public.match_dismiss_experience_prompt()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Sign in to continue'; end if;
  insert into public.match_feedback_prompt_state(user_id, dismissed_until, updated_at)
    values (v_uid, now() + interval '30 days', now())
  on conflict (user_id) do update set
    dismissed_until = now() + interval '30 days',
    updated_at = now();
end;
$$;
revoke all on function public.match_dismiss_experience_prompt() from public, anon;
grant execute on function public.match_dismiss_experience_prompt() to authenticated;

create or replace function public.match_submit_experience_feedback(
  p_statement_key text,
  p_rating integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Sign in to submit feedback'; end if;
  if p_statement_key not in ('safety','respect','connections','ease','recommend') then
    raise exception 'Invalid feedback statement';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'Choose a rating from 1 to 5 stars';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text, 5106));
  if exists (
    select 1 from public.match_feedback_prompt_state
    where user_id = v_uid
      and last_submitted_at > now() - interval '180 days'
  ) then
    raise exception 'Thank you. You have already shared feedback recently.';
  end if;

  insert into public.match_experience_feedback(user_id, statement_key, rating)
    values (v_uid, p_statement_key, p_rating);
  insert into public.match_feedback_prompt_state(
    user_id, dismissed_until, last_submitted_at, survey_count, updated_at
  ) values (v_uid, null, now(), 1, now())
  on conflict (user_id) do update set
    dismissed_until = null,
    last_submitted_at = now(),
    survey_count = public.match_feedback_prompt_state.survey_count + 1,
    updated_at = now();
end;
$$;
revoke all on function public.match_submit_experience_feedback(text, integer) from public, anon;
grant execute on function public.match_submit_experience_feedback(text, integer) to authenticated;

comment on table public.match_consistency_streaks is
  'Private member check-in streaks; each consecutive Lagos calendar day earns one star, with 25 coins at each five-day milestone.';
comment on table public.match_experience_feedback is
  'Private in-app experience ratings. Only the member and trusted service-role administrators can access individual responses.';

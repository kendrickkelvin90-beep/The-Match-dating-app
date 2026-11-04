#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"

U6=66666666-6666-4666-8666-666666666666
U7=77777777-7777-4777-8777-777777777777
U8=88888888-8888-4888-8888-888888888888
U9=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
SAME_KEY=membership:plus:concurrent-same-key-0001

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select set_config('request.jwt.claim.sub','$U6',false); select public.coin_buy_membership('plus','$SAME_KEY');" >/tmp/coin-same-a.log 2>&1 &
P1=$!
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select set_config('request.jwt.claim.sub','$U6',false); select public.coin_buy_membership('plus','$SAME_KEY');" >/tmp/coin-same-b.log 2>&1 &
P2=$!
wait "$P1"
wait "$P2"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select public.test_assert((select balance=700 from public.coin_wallets where user_id='$U6'),'concurrent same-key membership charged twice'); select public.test_assert((select count(*)=1 from public.coin_ledger where user_id='$U6' and idempotency_key='$SAME_KEY'),'concurrent same-key membership created duplicate ledger rows'); select public.test_assert((select expires_at between now()+interval '29 days' and now()+interval '31 days' from public.match_plus_memberships where user_id='$U6'),'concurrent same-key membership extended twice');"

# A higher tier must never be overwritten by a concurrent lower-tier purchase.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select set_config('request.jwt.claim.sub','$U7',false); select public.coin_buy_membership('plus','membership:plus:concurrent-tier-plus-0001');" >/tmp/coin-tier-plus.log 2>&1 &
P3=$!
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select set_config('request.jwt.claim.sub','$U7',false); select public.coin_buy_membership('annual','membership:annual:concurrent-tier-annual-0001');" >/tmp/coin-tier-annual.log 2>&1 &
P4=$!
if wait "$P3"; then
  :
else
  grep -q "Your current Match Plus tier is higher" /tmp/coin-tier-plus.log
fi
wait "$P4"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select public.test_assert((select tier='annual' from public.match_plus_memberships where user_id='$U7'),'concurrent membership purchases downgraded Annual'); select public.test_assert((select balance in (1900,2200) from public.coin_wallets where user_id='$U7'),'concurrent membership purchases deducted an unexpected amount');"

# Duplicate concurrent gift sends must produce one gift and one debit.
GIFT_REQUEST=cccccccc-cccc-4ccc-8ccc-cccccccccccc
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select set_config('request.jwt.claim.sub','$U8',false); select public.send_member_gift('$U9','rose',null,'$GIFT_REQUEST');" >/tmp/gift-send-a.log 2>&1 &
P5=$!
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select set_config('request.jwt.claim.sub','$U8',false); select public.send_member_gift('$U9','rose',null,'$GIFT_REQUEST');" >/tmp/gift-send-b.log 2>&1 &
P6=$!
wait "$P5"
wait "$P6"
GIFT_ID=$(psql "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -c "select id from public.member_gifts where sender_id='$U8' and request_id='$GIFT_REQUEST'")
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select public.test_assert((select balance=90 from public.coin_wallets where user_id='$U8'),'concurrent gift sends charged sender twice'); select public.test_assert((select count(*)=1 from public.member_gifts where sender_id='$U8' and request_id='$GIFT_REQUEST'),'concurrent gift sends created duplicate gifts');"

# Concurrent redemption permits only one credit.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select set_config('request.jwt.claim.sub','$U9',false); select public.redeem_member_gift('$GIFT_ID');" >/tmp/gift-redeem-a.log 2>&1 &
P7=$!
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select set_config('request.jwt.claim.sub','$U9',false); select public.redeem_member_gift('$GIFT_ID');" >/tmp/gift-redeem-b.log 2>&1 &
P8=$!
if wait "$P7"; then :; else :; fi
if wait "$P8"; then :; else :; fi
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select public.test_assert((select balance=8 from public.coin_wallets where user_id='$U9'),'concurrent gift redemption credited more than once'); select public.test_assert((select count(*)=1 from public.coin_ledger where user_id='$U9' and entry_type='gift_redeem'),'concurrent gift redemption wrote duplicate ledger rows'); select 'CONCURRENT COIN WALLET TESTS PASSED' as result;"

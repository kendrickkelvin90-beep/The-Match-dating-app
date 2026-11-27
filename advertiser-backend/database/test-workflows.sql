-- Integration smoke tests for advertiser-role isolation in the shared-project model.
-- Run only against the disposable CI PostgreSQL database.
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
('10000000-0000-4000-8000-000000000001','one@example.test',now(),'{"the_match_advertiser_registration":"v1","advertiser_type":"individual","display_name":"Advertiser One"}'),
('10000000-0000-4000-8000-000000000002','two@example.test',now(),'{"the_match_advertiser_registration":"v1","advertiser_type":"business","display_name":"Advertiser Two"}'),
('10000000-0000-4000-8000-000000000003','member@example.test',now(),'{"the_match_advertiser_registration":"v1","advertiser_type":"individual","display_name":"Should Not Convert"}');

insert into public.profiles(id) values ('10000000-0000-4000-8000-000000000003');

-- Simulate the trusted service-side enrollment endpoint. The Auth hook
-- must not create registry entries from user-editable metadata.
select public.register_advertiser_account('10000000-0000-4000-8000-000000000001');
select public.register_advertiser_account('10000000-0000-4000-8000-000000000002');

-- The profile trigger must reject a later attempt to turn an advertiser
-- identity into a Match dating-member account.
do $test$
begin
  begin
    insert into public.profiles(id) values ('10000000-0000-4000-8000-000000000001');
    raise exception 'Advertiser account was allowed to create a Match member profile';
  exception when check_violation then
    null;
  end;
  if exists (select 1 from public.profiles where id='10000000-0000-4000-8000-000000000001') then
    raise exception 'Advertiser account unexpectedly acquired a Match member profile';
  end if;
end;
$test$;
-- Ensure the Auth hook can evaluate the profile RLS helper in the
-- disposable integration database after its baseline schema is installed.
do $grant$
begin
  if to_regprocedure('private.is_dual_member_advertiser()') is not null then
    grant execute on function private.is_dual_member_advertiser() to supabase_auth_admin;
  end if;
end;
$grant$;

-- Existing Match members are explicitly allowed to add advertiser access
-- to the same Auth identity; their dating profile remains intact.
select public.register_advertiser_account('10000000-0000-4000-8000-000000000003');
do $test$
begin
  if not exists (select 1 from private.advertiser_auth_registry where user_id='10000000-0000-4000-8000-000000000003') then
    raise exception 'Existing Match member was not enrolled as an advertiser';
  end if;
end;
$test$;

set role supabase_auth_admin;
select public.custom_access_token_hook(jsonb_build_object(
  'user_id','10000000-0000-4000-8000-000000000001',
  'claims',jsonb_build_object('role','authenticated','user_metadata','{"the_match_advertiser_registration":"v1","advertiser_type":"individual","display_name":"Advertiser One"}'::jsonb)
));
select public.custom_access_token_hook(jsonb_build_object(
  'user_id','10000000-0000-4000-8000-000000000002',
  'claims',jsonb_build_object('role','authenticated','user_metadata','{"the_match_advertiser_registration":"v1","advertiser_type":"business","display_name":"Advertiser Two"}'::jsonb)
));
select public.custom_access_token_hook(jsonb_build_object(
  'user_id','10000000-0000-4000-8000-000000000003',
  'claims',jsonb_build_object('role','authenticated','user_metadata','{"the_match_advertiser_registration":"v1","advertiser_type":"individual","display_name":"Should Not Convert"}'::jsonb)
));
reset role;

do $test$
declare
  v_claims jsonb;
begin
  if not exists (select 1 from private.advertiser_auth_registry where user_id='10000000-0000-4000-8000-000000000003') then
    raise exception 'Existing Match member advertiser enrollment was not retained';
  end if;
  v_claims := public.custom_access_token_hook(jsonb_build_object(
    'user_id','10000000-0000-4000-8000-000000000003',
    'claims',jsonb_build_object('role','authenticated','user_metadata','{"the_match_advertiser_registration":"v1"}'::jsonb)
  ))->'claims';
  if v_claims->>'role' <> 'authenticated' or v_claims->>'user_role' <> 'advertiser' then
    raise exception 'Dual-role Match member did not retain authenticated access and advertiser permission';
  end if;
end;
$test$;

insert into public.advertiser_profiles(user_id,advertiser_type,display_name) values
('10000000-0000-4000-8000-000000000001','individual','Advertiser One'),
('10000000-0000-4000-8000-000000000002','business','Advertiser Two'),
('10000000-0000-4000-8000-000000000003','individual','Existing Match Member');

do $test$
begin
  if (select count(*) from private.advertiser_auth_registry) <> 3
     or (select count(*) from public.advertiser_profiles) <> 3 then
    raise exception 'Advertiser token hook did not isolate the two advertiser accounts';
  end if;
  if (select public.custom_access_token_hook(jsonb_build_object(
      'user_id','10000000-0000-4000-8000-000000000001',
      'claims',jsonb_build_object('role','authenticated')
    ))->'claims'->>'role') <> 'anon'
    or (select public.custom_access_token_hook(jsonb_build_object(
      'user_id','10000000-0000-4000-8000-000000000001',
      'claims',jsonb_build_object('role','authenticated')
    ))->'claims'->>'user_role') <> 'advertiser' then
    raise exception 'Advertiser JWT did not receive the supported anon role and advertiser custom claim';
  end if;
end;
$test$;

set role anon;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"anon","user_role":"advertiser"}',false);
do $test$
begin
  if has_table_privilege('anon','public.advertiser_profiles','select') then
    raise exception 'Advertiser browser must not directly read advertiser_profiles';
  end if;
end;
$test$;
reset role;

-- The Auth hook custom claim blocks member table reads even when a table's
-- ordinary permissive policy would otherwise allow an authenticated user.
set role anon;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"anon","user_role":"advertiser"}',false);
do $test$
begin
  if (select count(*) from public.profiles) <> 0 then
    raise exception 'Advertiser session could read Match member profiles';
  end if;
  if (select count(*) from public.legacy_open_table) <> 0 then
    raise exception 'Advertiser session could read a legacy public table without prior RLS';
  end if;
  perform set_config('request.path','profiles',false);
  begin
    perform public.match_advertiser_api_guard();
    raise exception 'Advertiser Data API guard did not reject a member table path';
  exception when sqlstate 'PGRST' then
    null;
  end;
  perform set_config('request.path','rpc/is_match_admin',false);
  begin
    perform public.match_advertiser_api_guard();
    raise exception 'Advertiser Data API guard allowed a member security-definer RPC';
  exception when sqlstate 'PGRST' then
    null;
  end;
  perform set_config('request.path','advertising_campaigns',false);
  perform public.match_advertiser_api_guard();
  perform set_config('request.path','rpc/get_advertising_campaign_metrics',false);
  begin
    perform public.match_advertiser_api_guard();
    raise exception 'Advertiser Data API guard allowed a server-only metrics RPC';
  exception when sqlstate 'PGRST' then
    null;
  end;
end;
$test$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","user_role":"advertiser"}',false);
do $test$
begin
  if (select count(*) from public.profiles) <> 1
     or (select count(*) from public.legacy_open_table) <> 1 then
    raise exception 'Normal Match member lost existing access to a public table';
  end if;
end;
$test$;
reset role;

insert into storage.objects(id) values ('20000000-0000-4000-8000-000000000001');
insert into realtime.messages(id) values ('20000000-0000-4000-8000-000000000001');


-- Storage and Realtime are also member-only surfaces.
set role anon;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"anon","user_role":"advertiser"}',false);
do $test$
begin
  if (select count(*) from storage.objects) <> 0
     or (select count(*) from realtime.messages) <> 0 then
    raise exception 'Advertiser session could read Match Storage or Realtime data';
  end if;
end;
$test$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated"}',false);
do $test$
begin
  if (select count(*) from storage.objects) <> 1
     or (select count(*) from realtime.messages) <> 1 then
    raise exception 'Normal Match member lost existing Storage or Realtime access';
  end if;
end;
$test$;
reset role;

insert into public.advertising_admins(user_id)
values ('10000000-0000-4000-8000-000000000001');

set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
do $test$
begin
  if not exists (select 1 from public.advertising_admins where user_id='10000000-0000-4000-8000-000000000001') then
    raise exception 'Advertising admin allowlist did not retain the seeded Match admin';
  end if;
end;
$test$;
reset role;

set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select * from public.create_advertising_campaign(
  '10000000-0000-4000-8000-000000000001',
  'Test campaign','A test creative for CI.','learn_more','https://example.test/offer',
  7,'immediate',null,'TMAD-CI-REFERENCE-001',now() + interval '24 hours'
);
select public.replace_advertising_creative(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001'),
  'image',
  'advertising/10000000-0000-4000-8000-000000000001/' ||
    (select id::text from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001') ||
    '/ci-image.jpg',
  null,'image/jpeg',100,null,null,null
);
select public.submit_advertising_payment(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001'),
  12000,'BANKREF-CI-0001',null
);
select public.admin_confirm_advertising_payment(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_payments where bank_transfer_reference = 'BANKREF-CI-0001'),
  'CI bank confirmation'
);
select public.admin_review_advertising_campaign(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001'),
  true,null
);
select public.record_advertising_event(
  (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001'),
  repeat('a',64),'impression'
);
select public.record_advertising_event(
  (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001'),
  repeat('a',64),'click'
);
select public.record_advertising_event(
  (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001'),
  repeat('a',64),'click'
);
do $test$
declare
  v_campaign uuid;
begin
  select id into v_campaign from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001';
  if public.record_advertising_event(v_campaign,repeat('a',64),'impression') then
    raise exception 'Duplicate daily impression was not deduplicated';
  end if;
  if (select status from public.advertising_campaigns where id = v_campaign) <> 'active' then
    raise exception 'Campaign did not activate after payment and approval';
  end if;
  if (select count(*) from public.advertising_clicks where campaign_id = v_campaign) <> 2
     or (select count(*) from public.advertising_unique_clicks where campaign_id = v_campaign) <> 1 then
    raise exception 'Total clicks and unique clicks were not tracked separately';
  end if;
end;
$test$;
reset role;

set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
do $test$
begin
  if (select count(*) from public.get_advertising_campaign_metrics(
    (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001'),
    '10000000-0000-4000-8000-000000000001'
  )) <> 1 then
    raise exception 'Server-side metrics RPC did not return the owned campaign';
  end if;
  if not exists (select 1 from public.get_advertising_campaign_metrics(
    (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001'),
    '10000000-0000-4000-8000-000000000001'
  ) m where m.clicks = 2 and m.unique_clicks = 1 and m.ctr = 100) then
    raise exception 'Server-side metrics did not calculate unique-click CTR correctly';
  end if;
end;
$test$;
reset role;

-- Verify impression and unique-click caps are rolling 24-hour windows, not calendar-day caps.
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
update public.advertising_impressions
set recorded_at=now()-interval '25 hours',
    event_day=(now() at time zone 'Africa/Lagos')::date - 1
where campaign_id=(select id from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001')
  and viewer_day_key=repeat('a',64);
do $test$
declare v_campaign uuid;
begin
  select id into v_campaign from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001';
  if not public.record_advertising_event(v_campaign,repeat('a',64),'impression') then
    raise exception 'Impression was not allowed after the rolling 24-hour window elapsed';
  end if;
  update public.advertising_impressions set recorded_at=now()-interval '23 hours'
  where id=(select id from public.advertising_impressions where campaign_id=v_campaign
    and viewer_day_key=repeat('a',64) order by recorded_at desc limit 1);
  if public.record_advertising_event(v_campaign,repeat('a',64),'impression') then
    raise exception 'Impression was allowed inside the rolling 24-hour window';
  end if;

  update public.advertising_unique_clicks
  set first_clicked_at=now()-interval '25 hours',
      event_day=(now() at time zone 'Africa/Lagos')::date - 1
  where campaign_id=v_campaign and viewer_day_key=repeat('a',64);
  if not public.record_advertising_event(v_campaign,repeat('a',64),'click') then
    raise exception 'Unique click was not allowed after the rolling 24-hour window elapsed';
  end if;
  update public.advertising_unique_clicks set first_clicked_at=now()-interval '23 hours'
  where id=(select id from public.advertising_unique_clicks where campaign_id=v_campaign
    and viewer_day_key=repeat('a',64) order by first_clicked_at desc limit 1);
  if public.record_advertising_event(v_campaign,repeat('a',64),'click') then
    raise exception 'Unique click was allowed inside the rolling 24-hour window';
  end if;
end;
$test$;
reset role;

set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select * from public.create_advertising_design_request(
  '10000000-0000-4000-8000-000000000001',
  'basic',null,'A clear promotional artwork brief for the design team.',
  'TMAD-DESIGN-CI-0001'
);
select public.submit_advertising_design_payment(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_design_payments where payment_reference = 'TMAD-DESIGN-CI-0001'),
  'BANKREF-DESIGN-CI-01'
);
select public.admin_confirm_advertising_design_payment(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_design_payments where payment_reference = 'TMAD-DESIGN-CI-0001'),
  'Design fee confirmed'
);
select public.admin_update_advertising_design_request(
  '10000000-0000-4000-8000-000000000001',
  (select design_request_id from public.advertising_design_payments where payment_reference = 'TMAD-DESIGN-CI-0001'),
  'in_progress',now() + interval '36 hours',null,'Delivery deadline agreed'
);
select public.admin_update_advertising_design_request(
  '10000000-0000-4000-8000-000000000001',
  (select design_request_id from public.advertising_design_payments where payment_reference = 'TMAD-DESIGN-CI-0001'),
  'first_draft_sent',null,null,null
);
select public.advertiser_request_design_revision(
  '10000000-0000-4000-8000-000000000001',
  (select design_request_id from public.advertising_design_payments where payment_reference = 'TMAD-DESIGN-CI-0001')
);
select public.admin_update_advertising_design_request(
  '10000000-0000-4000-8000-000000000001',
  (select design_request_id from public.advertising_design_payments where payment_reference = 'TMAD-DESIGN-CI-0001'),
  'first_draft_sent',null,null,'Revision completed'
);
select public.admin_update_advertising_design_request(
  '10000000-0000-4000-8000-000000000001',
  (select design_request_id from public.advertising_design_payments where payment_reference = 'TMAD-DESIGN-CI-0001'),
  'completed',null,
  'advertising-designs/10000000-0000-4000-8000-000000000001/' ||
    (select design_request_id::text from public.advertising_design_payments where payment_reference = 'TMAD-DESIGN-CI-0001') ||
    '/final.png',
  'Final artwork supplied'
);
do $test$
begin
  if not exists (
    select 1 from public.advertising_design_requests r
    join public.advertising_design_payments p on p.design_request_id = r.id
    where p.payment_reference = 'TMAD-DESIGN-CI-0001'
      and r.status = 'completed' and r.revisions_used = 1
      and p.status = 'confirmed'
  ) then
    raise exception 'Design service payment, revision or delivery lifecycle failed';
  end if;
end;
$test$;
reset role;

-- Duplicate transfer refund while the original campaign remains active.
select public.admin_record_duplicate_advertising_payment(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001'),
  '10000000-0000-4000-8000-000000000001',
  12000,'BANKREF-DUP-CI-0001','Additional transfer confirmed in bank statement'
);
select public.request_advertising_refund(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_payments where bank_transfer_reference = 'BANKREF-DUP-CI-0001'),
  'Duplicate transfer received'
);
select public.admin_review_advertising_refund(
  '10000000-0000-4000-8000-000000000001',
  (select r.id from public.advertising_refunds r join public.advertising_payments p on p.id = r.payment_id where p.bank_transfer_reference = 'BANKREF-DUP-CI-0001'),
  true,null
);
select public.admin_mark_advertising_refund_paid(
  '10000000-0000-4000-8000-000000000001',
  (select r.id from public.advertising_refunds r join public.advertising_payments p on p.id = r.payment_id where p.bank_transfer_reference = 'BANKREF-DUP-CI-0001'),
  'BANKREF-REFUND-CI-0001'
);
do $test$
begin
  if (select status from public.advertising_payments where bank_transfer_reference = 'BANKREF-DUP-CI-0001') <> 'refunded' then
    raise exception 'Duplicate transfer refund did not complete';
  end if;
  if (select payment_status from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001') <> 'confirmed' then
    raise exception 'Refunding a duplicate transfer incorrectly refunded the live campaign';
  end if;
end;
$test$;

-- Paid campaign rejection is refundable; the campaign reservation can be cancelled before payment.
select * from public.create_advertising_campaign(
  '10000000-0000-4000-8000-000000000001',
  'Rejected campaign','A campaign used to test rejection refunds.','learn_more','https://example.test/rejected',
  7,'immediate',null,'TMAD-CI-REFERENCE-002',now() + interval '24 hours'
);
select public.replace_advertising_creative(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-002'),
  'image',
  'advertising/10000000-0000-4000-8000-000000000001/' ||
    (select id::text from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-002') ||
    '/ci-image.jpg',
  null,'image/jpeg',100,null,null,null
);
select public.submit_advertising_payment(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-002'),
  12000,'BANKREF-CI-0002',null
);
select public.admin_confirm_advertising_payment(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_payments where bank_transfer_reference = 'BANKREF-CI-0002'),
  'CI bank confirmation'
);
select public.admin_review_advertising_campaign(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-002'),
  false,'Creative rejected for test'
);
select public.request_advertising_refund(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_payments where bank_transfer_reference = 'BANKREF-CI-0002'),
  'Advert rejected before launch'
);
select public.admin_review_advertising_refund(
  '10000000-0000-4000-8000-000000000001',
  (select r.id from public.advertising_refunds r join public.advertising_payments p on p.id = r.payment_id where p.bank_transfer_reference = 'BANKREF-CI-0002'),
  true,null
);
select public.admin_mark_advertising_refund_paid(
  '10000000-0000-4000-8000-000000000001',
  (select r.id from public.advertising_refunds r join public.advertising_payments p on p.id = r.payment_id where p.bank_transfer_reference = 'BANKREF-CI-0002'),
  'BANKREF-REFUND-CI-0002'
);
select * from public.create_advertising_campaign(
  '10000000-0000-4000-8000-000000000001',
  'Unpaid cancellation','This campaign should be cancelled without payment.','learn_more','https://example.test/cancel',
  7,'immediate',null,'TMAD-CI-REFERENCE-003',now() + interval '24 hours'
);
select public.cancel_unpaid_advertising_campaign(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-003')
);
do $test$
begin
  if (select payment_status from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-002') <> 'refunded' then
    raise exception 'Rejected paid campaign refund did not update payment status';
  end if;
  if (select status from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-003') <> 'cancelled' then
    raise exception 'Unpaid reservation was not cancelled';
  end if;
end;
$test$;
reset role;


-- Admin-reviewed campaign changes never alter the active advert before approval.
set role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.request_advertising_campaign_change(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001'),
  'Updated CI headline',null,null,'https://example.test/updated',null,null,
  'Advertiser supplied updated campaign details'
);
select public.attach_advertising_change_creative(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_campaign_change_requests where campaign_id =
    (select id from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001') and status='pending'),
  'image',
  'advertising/10000000-0000-4000-8000-000000000001/' ||
    (select id::text from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001') ||
    '/ci-replacement.jpg',
  null,'image/jpeg',100,null,null,null
);
do $test$
begin
  if (select headline from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001') <> 'Test campaign' then
    raise exception 'Pending campaign change altered the live campaign before review';
  end if;
  if (select count(*) from public.advertising_creatives where campaign_id =
      (select id from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001') and is_current) <> 1 then
    raise exception 'Pending creative replaced the live creative before review';
  end if;
end;
$test$;
select public.admin_review_advertising_campaign_change(
  '10000000-0000-4000-8000-000000000001',
  (select id from public.advertising_campaign_change_requests where campaign_id =
    (select id from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001') and status='pending'),
  true,null
);
do $test$
begin
  if (select headline from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001') <> 'Updated CI headline' then
    raise exception 'Approved campaign headline change was not applied';
  end if;
  if (select count(*) from public.advertising_creatives where campaign_id =
      (select id from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001') and is_current) <> 1 then
    raise exception 'Approved creative change did not preserve exactly one current creative';
  end if;
  if not exists (select 1 from public.advertising_campaign_change_requests
      where campaign_id=(select id from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001')
      and status='approved') then
    raise exception 'Campaign change approval was not recorded';
  end if;
end;
$test$;
reset role;

select private.process_advertising_campaign_clock_cron();

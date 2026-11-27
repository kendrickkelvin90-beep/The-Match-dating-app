-- Integration smoke tests for the isolated advertiser database.
-- Run only against the disposable CI PostgreSQL database.
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
('10000000-0000-4000-8000-000000000001','one@example.test',now(),'{"advertiser_type":"individual","display_name":"Advertiser One"}'),
('10000000-0000-4000-8000-000000000002','two@example.test',now(),'{"advertiser_type":"business","display_name":"Advertiser Two"}');

do $test$
begin
  if (select count(*) from public.advertiser_profiles) <> 2 then
    raise exception 'Advertiser Auth trigger did not create exactly two isolated profiles';
  end if;
end;
$test$;

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
do $test$
begin
  if (select count(*) from public.advertiser_profiles) <> 1 then
    raise exception 'Advertiser profile RLS did not isolate the current account';
  end if;
  if (select count(*) from public.advertiser_profiles where user_id = '10000000-0000-4000-8000-000000000002') <> 0 then
    raise exception 'Advertiser can read another advertiser profile';
  end if;
end;
$test$;
reset role;

insert into public.advertising_admins(user_id)
values ('10000000-0000-4000-8000-000000000001');

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
do $test$
begin
  if not private.is_advertising_admin() then
    raise exception 'Advertising admin helper did not recognize the seeded admin';
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

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
do $test$
begin
  if (select count(*) from public.get_my_advertising_campaign_metrics(
    (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001')
  )) <> 1 then
    raise exception 'Advertiser metrics RPC did not return the owned campaign';
  end if;
  if not exists (select 1 from public.get_my_advertising_campaign_metrics(
    (select id from public.advertising_campaigns where payment_reference = 'TMAD-CI-REFERENCE-001')
  ) m where m.clicks = 2 and m.unique_clicks = 1 and m.ctr = 100) then
    raise exception 'Advertiser metrics did not calculate unique-click CTR correctly';
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
  if (select headline from public.advertising_campaigns where payment_reference='TMAD-CI-REFERENCE-001') <> 'Approved campaign' then
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

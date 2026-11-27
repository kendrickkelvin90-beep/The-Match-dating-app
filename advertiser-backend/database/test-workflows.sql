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

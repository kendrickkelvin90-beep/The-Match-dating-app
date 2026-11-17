-- Validate one-time claims, eligibility, and sender preview behaviour.
\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
select public.test_assert(
  (select view_once and media_type='image' from public.claim_view_once_chat_media('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')),
  'eligible receiver should claim the View Once media'
);
select public.test_assert(
  (select opened_at is not null from public.chat_media where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'successful receiver claim must mark media opened'
);

do $$
begin
  begin
    perform * from public.claim_view_once_chat_media('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    raise exception 'TEST ASSERTION FAILED: repeated receiver claim unexpectedly succeeded';
  exception when others then
    if position('already been opened' in sqlerrm)=0 then raise; end if;
  end;
end;
$$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
select public.test_assert(
  (select count(*)=1 from public.claim_view_once_chat_media('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')),
  'sender should retain preview access without consuming receiver claim'
);

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',false);
do $$
begin
  begin
    perform * from public.claim_view_once_chat_media('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    raise exception 'TEST ASSERTION FAILED: ineligible chat member unexpectedly claimed media';
  exception when others then
    if position('Chat media access is unavailable' in sqlerrm)=0 then raise; end if;
  end;
end;
$$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000006',false);
select public.test_assert(
  (select count(*)=1 from public.claim_view_once_chat_media('cccccccc-cccc-4ccc-8ccc-cccccccccccc')),
  'mutual-match receiver should be allowed to claim View Once media'
);

select 'View Once claim regression tests passed' as result;

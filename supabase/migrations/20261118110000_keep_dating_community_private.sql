-- Keep a member's dating-community selection private.
-- Application security-definer functions can still call this helper as its owner;
-- ordinary authenticated clients must not be able to query another member's value.
begin;

revoke all on function private.member_dating_community(uuid)
  from public, anon, authenticated;

commit;

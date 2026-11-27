-- The Auth hook checks whether an enrolled advertiser already has a Match
-- profile. The profile policy calls this SECURITY DEFINER helper, so the
-- dedicated Auth administrator role must be allowed to execute it.
begin;
grant execute on function private.is_dual_member_advertiser() to supabase_auth_admin;
commit;

-- ROLLBACK ONLY if the advertiser pre-request guard was enabled from
-- enable-pre-request.sql and no other pre-request integration has replaced it.
alter role authenticator reset pgrst.db_pre_request;
notify pgrst, 'reload config';

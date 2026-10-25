-- Forward-only follow-up. Gives the Supabase API roles table privileges.
-- Some Supabase projects no longer grant access to new tables automatically,
-- so without this the signed-in role (authenticated) cannot read even its own
-- users row and sign-in fails with "This account has no access".
-- Row level security still decides which rows each person sees; this only
-- lets the roles reach the tables. Safe to run twice.

GRANT USAGE ON SCHEMA public TO authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated, service_role;

-- The audit log is append only: never grant change or delete on it.
REVOKE UPDATE, DELETE, TRUNCATE ON audit_log FROM authenticated, service_role;

-- Tables and views created by later migrations get the same access.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated, service_role;

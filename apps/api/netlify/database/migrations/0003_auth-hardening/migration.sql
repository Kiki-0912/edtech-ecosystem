-- Generated from apps/api/src/store/migrations.ts by `npm run db:netlify-migrations`.
-- Do not edit by hand.
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TEXT NOT NULL
);
ALTER TABLE users ADD COLUMN token_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE sms_verification_codes ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;

INSERT INTO schema_migrations (version, name, applied_at)
VALUES (3, 'auth_hardening',
        to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
ON CONFLICT (version) DO NOTHING;

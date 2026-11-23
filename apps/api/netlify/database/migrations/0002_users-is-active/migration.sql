-- Generated from apps/api/src/store/migrations.ts by `npm run db:netlify-migrations`.
-- Do not edit by hand.
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TEXT NOT NULL
);
ALTER TABLE users ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE;

INSERT INTO schema_migrations (version, name, applied_at)
VALUES (2, 'users_is_active',
        to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
ON CONFLICT (version) DO NOTHING;

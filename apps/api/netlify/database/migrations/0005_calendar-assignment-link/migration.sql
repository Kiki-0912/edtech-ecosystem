-- Generated from apps/api/src/store/migrations.ts by `npm run db:netlify-migrations`.
-- Do not edit by hand.
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TEXT NOT NULL
);
ALTER TABLE calendar_events
  ADD COLUMN assignment_id TEXT NULL REFERENCES assignments (id) ON DELETE CASCADE;
CREATE UNIQUE INDEX idx_calendar_assignment ON calendar_events (assignment_id);

INSERT INTO schema_migrations (version, name, applied_at)
VALUES (5, 'calendar_assignment_link',
        to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
ON CONFLICT (version) DO NOTHING;

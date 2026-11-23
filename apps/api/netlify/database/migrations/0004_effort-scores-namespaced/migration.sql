-- Generated from apps/api/src/store/migrations.ts by `npm run db:netlify-migrations`.
-- Do not edit by hand.
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TEXT NOT NULL
);
UPDATE effort_scores namespaced
   SET seq = legacy.seq
  FROM effort_scores legacy
 WHERE namespaced.session_id = legacy.student_id || ':' || legacy.session_id;
DELETE FROM effort_scores legacy
 USING effort_scores namespaced
 WHERE namespaced.session_id = legacy.student_id || ':' || legacy.session_id;
UPDATE effort_scores
   SET session_id = student_id || ':' || session_id
 WHERE left(session_id, length(student_id) + 1) <> student_id || ':';

INSERT INTO schema_migrations (version, name, applied_at)
VALUES (4, 'effort_scores_namespaced',
        to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
ON CONFLICT (version) DO NOTHING;

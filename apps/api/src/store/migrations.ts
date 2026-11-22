// Postgres schema migrations, applied in order by `runMigrations()` and
// recorded in `schema_migrations`. They are embedded as strings (not .sql
// files) so the Vercel function bundle needs no filesystem access.
//
// Timestamps are stored as ISO-8601 TEXT on purpose: clients send local
// date-times without a zone (Flutter `toIso8601String()`), and the API must
// return them unchanged, exactly as the in-memory store does.
//
// Every table has a `seq BIGSERIAL` column used as an ORDER BY tie-breaker so
// listings keep insertion order, matching the in-memory store.
//
// Never edit a migration that has shipped; append a new one instead.

/** Bookkeeping table shared by the API's runner and the Netlify migration files. */
export const SCHEMA_MIGRATIONS_DDL = `CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TEXT NOT NULL
)`;

/**
 * SQL for Netlify Database's deploy-time migration file for one migration:
 * the schema change plus its `schema_migrations` record, so the API's runner
 * sees it as applied. Generated into apps/api/netlify/database/migrations.
 */
export function netlifyMigrationSql(migration: Migration): string {
  return `-- Generated from apps/api/src/store/migrations.ts by \`npm run db:netlify-migrations\`.
-- Do not edit by hand.
${SCHEMA_MIGRATIONS_DDL};
${migration.sql.trim()}

INSERT INTO schema_migrations (version, name, applied_at)
VALUES (${migration.version}, '${migration.name}',
        to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
ON CONFLICT (version) DO NOTHING;
`;
}

/** Folder name Netlify expects: zero-padded sequence + slug. */
export function netlifyMigrationDir(migration: Migration): string {
  return `${String(migration.version).padStart(4, "0")}_${migration.name.replaceAll("_", "-")}`;
}

export interface Migration {
  version: number;
  name: string;
  sql: string;
}

export const MIGRATIONS: Migration[] = [
  {
    version: 1,
    name: "initial_schema",
    sql: `
CREATE TABLE users (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  email TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL CHECK (role IN ('student', 'teacher', 'admin')),
  course_ids JSONB NOT NULL DEFAULT '[]',
  password_hash TEXT,
  is_phone_verified BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TEXT NOT NULL
);
-- Phone-only and email-only sign-ups store '' for the missing field.
CREATE UNIQUE INDEX users_email_unique ON users (email) WHERE email <> '';
CREATE UNIQUE INDEX users_phone_unique ON users (phone) WHERE phone <> '';

CREATE TABLE courses (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  code TEXT NOT NULL,
  teacher_id TEXT NOT NULL REFERENCES users (id),
  student_ids JSONB NOT NULL DEFAULT '[]',
  term TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE colleges (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  short_name TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE departments (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  college_id TEXT NOT NULL REFERENCES colleges (id),
  name TEXT NOT NULL,
  code TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT '3 Years',
  duration_months INTEGER NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_departments_college ON departments (college_id);

CREATE TABLE assignments (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  course_id TEXT NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  brief TEXT NOT NULL,
  due_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('draft', 'open', 'closed')),
  created_at TEXT NOT NULL
);
CREATE INDEX idx_assignments_course ON assignments (course_id);

CREATE TABLE submissions (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  assignment_id TEXT NOT NULL REFERENCES assignments (id) ON DELETE CASCADE,
  student_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'submitted', 'graded', 'late', 'missing')),
  submitted_at TEXT,
  attachments JSONB NOT NULL DEFAULT '[]',
  grade DOUBLE PRECISION,
  effort_score INTEGER,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_submissions_assignment ON submissions (assignment_id);
CREATE INDEX idx_submissions_student ON submissions (student_id);

CREATE TABLE calendar_events (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  course_id TEXT REFERENCES courses (id) ON DELETE CASCADE,
  department_id TEXT REFERENCES departments (id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  kind TEXT NOT NULL,
  starts_at TEXT NOT NULL,
  ends_at TEXT
);
CREATE INDEX idx_calendar_course ON calendar_events (course_id);

CREATE TABLE chat_channels (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  course_id TEXT NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'discussion' CHECK (kind IN ('announcement', 'discussion')),
  member_ids JSONB NOT NULL DEFAULT '[]'
);

CREATE TABLE chat_messages (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  channel_id TEXT NOT NULL REFERENCES chat_channels (id) ON DELETE CASCADE,
  author_id TEXT NOT NULL REFERENCES users (id),
  body TEXT NOT NULL,
  sent_at TEXT NOT NULL
);
CREATE INDEX idx_messages_channel ON chat_messages (channel_id, sent_at);

-- Events are kept with their batch for replay; the signature fields are the
-- client's originals.
CREATE TABLE telemetry_batches (
  seq BIGSERIAL,
  batch_id TEXT PRIMARY KEY,
  student_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  assignment_id TEXT NOT NULL REFERENCES assignments (id) ON DELETE CASCADE,
  events JSONB NOT NULL,
  client_signature TEXT NOT NULL,
  client_public_key TEXT NOT NULL,
  created_at TEXT NOT NULL,
  received_at TEXT NOT NULL
);
CREATE INDEX idx_telemetry_student_assignment ON telemetry_batches (student_id, assignment_id);

CREATE TABLE effort_scores (
  session_id TEXT PRIMARY KEY,
  assignment_id TEXT NOT NULL,
  student_id TEXT NOT NULL,
  score INTEGER NOT NULL DEFAULT 0,
  keystrokes INTEGER NOT NULL DEFAULT 0,
  pastes INTEGER NOT NULL DEFAULT 0,
  paste_volume INTEGER NOT NULL DEFAULT 0,
  ai_tab_switches INTEGER NOT NULL DEFAULT 0,
  active_seconds INTEGER NOT NULL DEFAULT 0,
  computed_at TEXT NOT NULL,
  seq BIGSERIAL
);
CREATE INDEX idx_effort_student_assignment ON effort_scores (student_id, assignment_id);

CREATE TABLE integrity_flags (
  seq BIGSERIAL,
  student_id TEXT NOT NULL,
  assignment_id TEXT NOT NULL,
  flags JSONB NOT NULL DEFAULT '[]',
  PRIMARY KEY (student_id, assignment_id)
);

-- No FK on phone: codes are transient; routes validate the account.
CREATE TABLE sms_verification_codes (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  phone TEXT NOT NULL,
  code TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_sms_codes_phone ON sms_verification_codes (phone);

CREATE TABLE attendance_records (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  course_id TEXT NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
  student_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  date TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('present', 'absent', 'late', 'excused')),
  marked_by TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  UNIQUE (course_id, student_id, date)
);
CREATE INDEX idx_attendance_student ON attendance_records (student_id);

CREATE TABLE teacher_notes (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  course_id TEXT NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
  book_name TEXT NOT NULL,
  course_code TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  author_id TEXT NOT NULL REFERENCES users (id),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX idx_notes_course ON teacher_notes (course_id);
CREATE INDEX idx_notes_code ON teacher_notes (course_code);

CREATE TABLE student_departments (
  seq BIGSERIAL,
  id TEXT PRIMARY KEY,
  student_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  department_id TEXT NOT NULL REFERENCES departments (id) ON DELETE CASCADE,
  enrolled_at TEXT NOT NULL,
  enrolled_by TEXT NOT NULL,
  UNIQUE (student_id, department_id)
);
CREATE INDEX idx_student_dept_dept ON student_departments (department_id);
`,
  },
];

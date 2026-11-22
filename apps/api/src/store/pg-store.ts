import { randomUUID } from "node:crypto";
import pg from "pg";
import type { Store } from "./db";
import type {
  Attachment,
  AttendanceRecord,
  CalendarEventKind,
  DepartmentCategory,
  EffortScore,
  IntegrityFlag,
  Role,
  Row,
  SeedOptions,
  SignedTelemetryBatch,
  SubmissionStatus,
  Tables,
} from "./memory-store";
import { buildSeedRows, mappers } from "./memory-store";
import { MIGRATIONS } from "./migrations";

const {
  toAssignment,
  toAttendanceRecord,
  toCalendarEvent,
  toChannel,
  toCollege,
  toCourse,
  toDepartment,
  toMessage,
  toStudentDepartment,
  toSubmission,
  toTeacherNote,
  toUser,
} = mappers;

type Queryable = Pick<pg.Pool | pg.PoolClient, "query">;

// Arbitrary constant so concurrent cold starts don't migrate at the same time.
const MIGRATION_LOCK_ID = 727_001;

function nowISO() {
  return new Date().toISOString();
}

export function createPool(connectionString: string): pg.Pool {
  return new pg.Pool({
    connectionString,
    // Serverless instances each hold their own pool; keep it small.
    max: Number.parseInt(process.env.DATABASE_POOL_MAX ?? "5", 10) || 5,
  });
}

async function withTransaction<T>(
  pool: pg.Pool,
  work: (client: pg.PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await work(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

/** Apply pending migrations. Safe to call from several processes at once. */
export async function runMigrations(pool: pg.Pool): Promise<number[]> {
  const client = await pool.connect();
  const applied: number[] = [];
  try {
    await client.query("SELECT pg_advisory_lock($1)", [MIGRATION_LOCK_ID]);
    await client.query(
      `CREATE TABLE IF NOT EXISTS schema_migrations (
         version INTEGER PRIMARY KEY,
         name TEXT NOT NULL,
         applied_at TEXT NOT NULL
       )`,
    );
    const { rows } = await client.query<{ version: number }>(
      "SELECT version FROM schema_migrations",
    );
    const done = new Set(rows.map((row) => row.version));
    for (const migration of MIGRATIONS) {
      if (done.has(migration.version)) continue;
      await client.query("BEGIN");
      try {
        await client.query(migration.sql);
        await client.query(
          "INSERT INTO schema_migrations (version, name, applied_at) VALUES ($1, $2, $3)",
          [migration.version, migration.name, nowISO()],
        );
        await client.query("COMMIT");
        applied.push(migration.version);
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      }
    }
  } finally {
    await client.query("SELECT pg_advisory_unlock($1)", [MIGRATION_LOCK_ID]).catch(() => {});
    client.release();
  }
  return applied;
}

async function insertRows(db: Queryable, table: string, rows: Row[]): Promise<void> {
  for (const row of rows) {
    const columns = Object.keys(row);
    const placeholders = columns.map((_, index) => `$${index + 1}`);
    await db.query(
      `INSERT INTO ${table} (${columns.join(", ")}) VALUES (${placeholders.join(", ")})
       ON CONFLICT DO NOTHING`,
      columns.map((column) => row[column]),
    );
  }
}

/**
 * Seed a fresh database. Reference data (college + departments) is always
 * inserted; demo users, courses and activity only when `includeDemo` is set
 * and the users table is still empty. Idempotent.
 */
export async function seedDatabase(
  pool: pg.Pool,
  options: { includeDemo: boolean } & SeedOptions,
): Promise<{ seededDemo: boolean }> {
  const seed: Tables = buildSeedRows(options);
  return withTransaction(pool, async (client) => {
    await insertRows(client, "colleges", seed.colleges);
    const { rows } = await client.query("SELECT 1 FROM departments LIMIT 1");
    if (rows.length === 0) {
      await insertRows(client, "departments", seed.departments);
    }

    if (!options.includeDemo) return { seededDemo: false };
    const users = await client.query("SELECT 1 FROM users LIMIT 1");
    if (users.rows.length > 0) return { seededDemo: false };

    // Order matters: parents before children (foreign keys).
    await insertRows(client, "users", seed.users);
    await insertRows(client, "courses", seed.courses);
    await insertRows(client, "assignments", seed.assignments);
    await insertRows(client, "submissions", seed.submissions);
    await insertRows(client, "calendar_events", seed.calendar_events);
    await insertRows(client, "chat_channels", seed.chat_channels);
    await insertRows(client, "chat_messages", seed.chat_messages);
    await insertRows(client, "attendance_records", seed.attendance_records);
    await insertRows(client, "teacher_notes", seed.teacher_notes);
    await insertRows(client, "student_departments", seed.student_departments);
    return { seededDemo: true };
  });
}

/** Build `SET a = $2, b = $3` from a column→value map, skipping undefined. */
function setClause(
  values: Record<string, unknown>,
  offset: number,
): { sql: string; params: unknown[] } {
  const entries = Object.entries(values).filter(([, value]) => value !== undefined);
  return {
    sql: entries.map(([column], index) => `${column} = $${index + offset}`).join(", "),
    params: entries.map(([, value]) => value),
  };
}

function toEffortScore(row: Row): EffortScore {
  return {
    sessionId: row.session_id,
    assignmentId: row.assignment_id,
    studentId: row.student_id,
    score: row.score,
    keystrokes: row.keystrokes,
    pastes: row.pastes,
    pasteVolume: row.paste_volume,
    aiTabSwitches: row.ai_tab_switches,
    activeSeconds: row.active_seconds,
    computedAt: row.computed_at,
  };
}

function toTelemetryBatch(row: Row): SignedTelemetryBatch {
  return {
    batchId: row.batch_id,
    studentId: row.student_id,
    assignmentId: row.assignment_id,
    events: row.events,
    clientSignature: row.client_signature,
    clientPublicKey: row.client_public_key,
    createdAt: row.created_at,
  };
}

export function createPgStore(pool: pg.Pool): Store {
  const many = async (sql: string, params: unknown[] = []) =>
    (await pool.query(sql, params)).rows as Row[];
  const one = async (sql: string, params: unknown[] = []) =>
    (await many(sql, params))[0] as Row | undefined;

  const store: Store = {
    // ---------------- Users ----------------
    async getUsers() {
      return (await many("SELECT * FROM users ORDER BY seq")).map(toUser);
    },
    async getUser(userId) {
      const row = await one("SELECT * FROM users WHERE id = $1", [userId]);
      return row ? toUser(row) : undefined;
    },
    async getUserByPhone(phone) {
      const row = await one("SELECT * FROM users WHERE phone = $1 ORDER BY seq LIMIT 1", [
        phone,
      ]);
      return row ? toUser(row) : undefined;
    },
    async getUserAuthByPhone(phone) {
      const row = await one(
        "SELECT id, password_hash FROM users WHERE phone = $1 ORDER BY seq LIMIT 1",
        [phone],
      );
      return row ? { id: row.id, passwordHash: row.password_hash } : undefined;
    },
    async getUserAuthByEmail(email) {
      const row = await one(
        "SELECT id, password_hash FROM users WHERE email = $1 ORDER BY seq LIMIT 1",
        [email],
      );
      return row ? { id: row.id, passwordHash: row.password_hash } : undefined;
    },
    async createUser(input) {
      const row = await one(
        `INSERT INTO users (id, display_name, email, phone, role, course_ids, password_hash,
                            is_phone_verified, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
        [
          input.id,
          input.displayName,
          input.email,
          input.phone,
          input.role satisfies Role,
          JSON.stringify(input.courseIds),
          input.passwordHash,
          Boolean(input.isPhoneVerified),
          input.createdAt || nowISO(),
        ],
      );
      return toUser(row!);
    },
    async updateUser(userId, updates) {
      const { sql, params } = setClause(
        {
          display_name: updates.displayName,
          email: updates.email,
          phone: updates.phone,
          password_hash: updates.passwordHash,
          is_phone_verified:
            updates.isPhoneVerified === undefined ? undefined : Boolean(updates.isPhoneVerified),
        },
        2,
      );
      if (!sql) return;
      await pool.query(`UPDATE users SET ${sql} WHERE id = $1`, [userId, ...params]);
    },

    // ---------------- Courses ----------------
    async getCourses() {
      return (await many("SELECT * FROM courses ORDER BY seq")).map(toCourse);
    },
    async getCourse(courseId) {
      const row = await one("SELECT * FROM courses WHERE id = $1", [courseId]);
      return row ? toCourse(row) : undefined;
    },
    async getAssignmentsByCourse(courseId) {
      return (
        await many(
          `SELECT * FROM assignments WHERE course_id = $1
           ORDER BY due_at COLLATE "C", seq`,
          [courseId],
        )
      ).map(toAssignment);
    },
    async addStudentToCourse(courseId, studentId) {
      await pool.query(
        `UPDATE courses SET student_ids = student_ids || to_jsonb($2::text)
         WHERE id = $1 AND NOT student_ids ? $2`,
        [courseId, studentId],
      );
    },
    async removeStudentFromCourse(courseId, studentId) {
      await pool.query("UPDATE courses SET student_ids = student_ids - $2::text WHERE id = $1", [
        courseId,
        studentId,
      ]);
    },

    // ---------------- College and departments ----------------
    async getColleges() {
      return (await many("SELECT * FROM colleges ORDER BY seq")).map(toCollege);
    },
    async getCollege(collegeId) {
      const row = await one("SELECT * FROM colleges WHERE id = $1", [collegeId]);
      return row ? toCollege(row) : undefined;
    },
    async getDepartments(collegeId) {
      return (
        await many("SELECT * FROM departments WHERE college_id = $1 ORDER BY seq", [collegeId])
      ).map(toDepartment);
    },
    async getDepartment(departmentId) {
      const row = await one("SELECT * FROM departments WHERE id = $1", [departmentId]);
      return row ? toDepartment(row) : undefined;
    },
    async createDepartment(input) {
      const row = await one(
        `INSERT INTO departments (id, college_id, name, code, category, duration_months, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
        [
          randomUUID(),
          input.collegeId,
          input.name,
          input.code,
          input.category satisfies DepartmentCategory,
          input.durationMonths,
          nowISO(),
        ],
      );
      return toDepartment(row!);
    },
    async updateDepartment(departmentId, updates) {
      const { sql, params } = setClause(
        {
          name: updates.name,
          code: updates.code,
          category: updates.category,
          duration_months: updates.durationMonths,
        },
        2,
      );
      const row = sql
        ? await one(`UPDATE departments SET ${sql} WHERE id = $1 RETURNING *`, [
            departmentId,
            ...params,
          ])
        : await one("SELECT * FROM departments WHERE id = $1", [departmentId]);
      return row ? toDepartment(row) : undefined;
    },
    async deleteDepartment(departmentId) {
      // Enrollments cascade; calendar events fall back to "all departments".
      const result = await pool.query("DELETE FROM departments WHERE id = $1", [departmentId]);
      return (result.rowCount ?? 0) > 0;
    },

    // ---------------- Assignments and submissions ----------------
    async getAssignment(assignmentId) {
      const row = await one("SELECT * FROM assignments WHERE id = $1", [assignmentId]);
      return row ? toAssignment(row) : undefined;
    },
    async getSubmissionsByAssignment(assignmentId) {
      return (
        await many("SELECT * FROM submissions WHERE assignment_id = $1 ORDER BY seq", [
          assignmentId,
        ])
      ).map(toSubmission);
    },
    async getSubmission(submissionId) {
      const row = await one("SELECT * FROM submissions WHERE id = $1", [submissionId]);
      return row ? toSubmission(row) : undefined;
    },
    async createSubmission(input) {
      const attachments: Attachment[] = input.attachments.map((attachment) => ({
        ...attachment,
        id: attachment.id || randomUUID(),
      }));
      const row = await one(
        `INSERT INTO submissions (id, assignment_id, student_id, status, submitted_at,
                                  attachments, grade, effort_score, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, NULL, NULL, $7) RETURNING *`,
        [
          randomUUID(),
          input.assignmentId,
          input.studentId,
          input.status satisfies SubmissionStatus,
          input.submittedAt,
          JSON.stringify(attachments),
          nowISO(),
        ],
      );
      return toSubmission(row!);
    },
    async updateSubmission(submissionId, updates) {
      const { sql, params } = setClause(
        {
          status: updates.status,
          submitted_at: updates.submittedAt,
          attachments:
            updates.attachments === undefined ? undefined : JSON.stringify(updates.attachments),
          grade: updates.grade,
          effort_score: updates.effortScore,
        },
        2,
      );
      if (!sql) return;
      await pool.query(`UPDATE submissions SET ${sql} WHERE id = $1`, [submissionId, ...params]);
    },

    // ---------------- Calendar ----------------
    async getCalendarEvents(courseIds, departmentId) {
      let rows: Row[];
      if (departmentId) {
        rows = await many(
          `SELECT * FROM calendar_events
           WHERE department_id = $1 OR department_id IS NULL
           ORDER BY starts_at COLLATE "C", seq`,
          [departmentId],
        );
      } else if (courseIds.size === 0) {
        rows = await many(
          `SELECT * FROM calendar_events WHERE course_id IS NULL
           ORDER BY starts_at COLLATE "C", seq`,
        );
      } else {
        rows = await many(
          `SELECT * FROM calendar_events
           WHERE course_id IS NULL OR course_id = ANY($1::text[])
           ORDER BY starts_at COLLATE "C", seq`,
          [[...courseIds]],
        );
      }
      return rows.map(toCalendarEvent);
    },
    async createCalendarEvent(input) {
      const row = await one(
        `INSERT INTO calendar_events (id, course_id, department_id, title, kind, starts_at, ends_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
        [
          randomUUID(),
          input.courseId ?? null,
          input.departmentId ?? null,
          input.title,
          input.kind satisfies CalendarEventKind,
          input.startsAt,
          input.endsAt ?? null,
        ],
      );
      return toCalendarEvent(row!);
    },
    async updateCalendarEvent(eventId, updates) {
      const { sql, params } = setClause(
        {
          title: updates.title,
          kind: updates.kind,
          starts_at: updates.startsAt,
          ends_at: updates.endsAt,
          department_id: updates.departmentId,
          course_id: updates.courseId,
        },
        2,
      );
      const row = sql
        ? await one(`UPDATE calendar_events SET ${sql} WHERE id = $1 RETURNING *`, [
            eventId,
            ...params,
          ])
        : await one("SELECT * FROM calendar_events WHERE id = $1", [eventId]);
      return row ? toCalendarEvent(row) : undefined;
    },
    async deleteCalendarEvent(eventId) {
      const result = await pool.query("DELETE FROM calendar_events WHERE id = $1", [eventId]);
      return (result.rowCount ?? 0) > 0;
    },

    // ---------------- Chat ----------------
    async getChannelsByCourse(courseId) {
      return (
        await many("SELECT * FROM chat_channels WHERE course_id = $1 ORDER BY seq", [courseId])
      ).map(toChannel);
    },
    async getChannel(channelId) {
      const row = await one("SELECT * FROM chat_channels WHERE id = $1", [channelId]);
      return row ? toChannel(row) : undefined;
    },
    async getMessages(channelId) {
      return (
        await many(
          `SELECT * FROM chat_messages WHERE channel_id = $1
           ORDER BY sent_at COLLATE "C", seq`,
          [channelId],
        )
      ).map(toMessage);
    },
    async createMessage(input) {
      const row = await one(
        `INSERT INTO chat_messages (id, channel_id, author_id, body, sent_at)
         VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [randomUUID(), input.channelId, input.authorId, input.body, nowISO()],
      );
      return toMessage(row!);
    },

    // ---------------- Telemetry, effort and integrity ----------------
    async getTelemetryBatches() {
      return (await many("SELECT * FROM telemetry_batches ORDER BY seq")).map(toTelemetryBatch);
    },
    async hasTelemetryBatch(studentId, assignmentId) {
      const row = await one(
        "SELECT 1 FROM telemetry_batches WHERE student_id = $1 AND assignment_id = $2 LIMIT 1",
        [studentId, assignmentId],
      );
      return row !== undefined;
    },
    async createTelemetryBatch(batch) {
      // Idempotent: the extension retries a batch whose response was lost.
      await pool.query(
        `INSERT INTO telemetry_batches (batch_id, student_id, assignment_id, events,
                                        client_signature, client_public_key, created_at,
                                        received_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (batch_id) DO NOTHING`,
        [
          batch.batchId,
          batch.studentId,
          batch.assignmentId,
          JSON.stringify(batch.events),
          batch.clientSignature,
          batch.clientPublicKey,
          batch.createdAt,
          nowISO(),
        ],
      );
    },
    async getEffortScore(studentId, assignmentId) {
      // First recorded session, matching the in-memory store.
      const row = await one(
        `SELECT * FROM effort_scores WHERE student_id = $1 AND assignment_id = $2
         ORDER BY seq LIMIT 1`,
        [studentId, assignmentId],
      );
      return row ? toEffortScore(row) : undefined;
    },
    async setEffortScore(score) {
      await pool.query(
        `INSERT INTO effort_scores (session_id, assignment_id, student_id, score, keystrokes,
                                    pastes, paste_volume, ai_tab_switches, active_seconds,
                                    computed_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         ON CONFLICT (session_id) DO UPDATE SET
           assignment_id = EXCLUDED.assignment_id,
           student_id = EXCLUDED.student_id,
           score = EXCLUDED.score,
           keystrokes = EXCLUDED.keystrokes,
           pastes = EXCLUDED.pastes,
           paste_volume = EXCLUDED.paste_volume,
           ai_tab_switches = EXCLUDED.ai_tab_switches,
           active_seconds = EXCLUDED.active_seconds,
           computed_at = EXCLUDED.computed_at`,
        [
          score.sessionId,
          score.assignmentId,
          score.studentId,
          score.score,
          score.keystrokes,
          score.pastes,
          score.pasteVolume,
          score.aiTabSwitches,
          score.activeSeconds,
          score.computedAt,
        ],
      );
    },
    async getIntegrityFlags(studentId, assignmentId) {
      const row = await one(
        "SELECT flags FROM integrity_flags WHERE student_id = $1 AND assignment_id = $2",
        [studentId, assignmentId],
      );
      return row ? ([...row.flags] as IntegrityFlag[]) : [];
    },
    async setIntegrityFlags(studentId, assignmentId, flags) {
      await pool.query(
        `INSERT INTO integrity_flags (student_id, assignment_id, flags) VALUES ($1, $2, $3)
         ON CONFLICT (student_id, assignment_id) DO UPDATE SET flags = EXCLUDED.flags`,
        [studentId, assignmentId, JSON.stringify(flags)],
      );
    },

    // ---------------- SMS verification ----------------
    async createSmsCode(input) {
      await pool.query(
        `INSERT INTO sms_verification_codes (id, phone, code, expires_at, created_at)
         VALUES ($1, $2, $3, $4, $5)`,
        [input.id, input.phone, input.code, input.expiresAt, input.createdAt || nowISO()],
      );
      return input;
    },
    async verifySmsCode(phone, code) {
      // Codes are single use: consume the match whether or not it has expired.
      const row = await one(
        `DELETE FROM sms_verification_codes
         WHERE id = (SELECT id FROM sms_verification_codes
                     WHERE phone = $1 AND code = $2 ORDER BY seq LIMIT 1)
         RETURNING expires_at`,
        [phone, code],
      );
      if (!row) return false;
      return new Date(row.expires_at).getTime() > Date.now();
    },
    async markPhoneVerified(phone) {
      await pool.query("UPDATE users SET is_phone_verified = TRUE WHERE phone = $1", [phone]);
    },

    // ---------------- Attendance ----------------
    async getAttendanceRecords(courseId, date) {
      const rows = await many(
        `SELECT * FROM attendance_records
         WHERE ($1::text IS NULL OR course_id = $1) AND ($2::text IS NULL OR date = $2)
         ORDER BY date COLLATE "C" DESC, seq`,
        [courseId || null, date || null],
      );
      return rows.map(toAttendanceRecord);
    },
    async getAttendanceRecord(id) {
      const row = await one("SELECT * FROM attendance_records WHERE id = $1", [id]);
      return row ? toAttendanceRecord(row) : undefined;
    },
    async upsertAttendanceRecord(input) {
      const row = await one(
        `INSERT INTO attendance_records (id, course_id, student_id, date, status, marked_by,
                                         notes, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (course_id, student_id, date) DO UPDATE SET
           status = EXCLUDED.status,
           marked_by = EXCLUDED.marked_by,
           notes = EXCLUDED.notes
         RETURNING *`,
        [
          input.id || randomUUID(),
          input.courseId,
          input.studentId,
          input.date,
          input.status satisfies AttendanceRecord["status"],
          input.markedBy,
          input.notes ?? "",
          nowISO(),
        ],
      );
      return toAttendanceRecord(row!);
    },

    // ---------------- Teacher notes ----------------
    async getTeacherNotes(courseId, courseCode) {
      const rows = await many(
        `SELECT * FROM teacher_notes
         WHERE ($1::text IS NULL OR course_id = $1) AND ($2::text IS NULL OR course_code = $2)
         ORDER BY created_at COLLATE "C" DESC, seq`,
        [courseId || null, courseCode || null],
      );
      return rows.map(toTeacherNote);
    },
    async getTeacherNote(id) {
      const row = await one("SELECT * FROM teacher_notes WHERE id = $1", [id]);
      return row ? toTeacherNote(row) : undefined;
    },
    async upsertTeacherNote(input) {
      const now = nowISO();
      // An update keeps the note's course and author, like the in-memory store.
      const row = await one(
        `INSERT INTO teacher_notes (id, course_id, book_name, course_code, title, content,
                                    author_id, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)
         ON CONFLICT (id) DO UPDATE SET
           book_name = EXCLUDED.book_name,
           course_code = EXCLUDED.course_code,
           title = EXCLUDED.title,
           content = EXCLUDED.content,
           updated_at = EXCLUDED.updated_at
         RETURNING *`,
        [
          input.id || randomUUID(),
          input.courseId,
          input.bookName,
          input.courseCode,
          input.title,
          input.content,
          input.authorId,
          now,
        ],
      );
      return toTeacherNote(row!);
    },
    async deleteTeacherNote(id) {
      await pool.query("DELETE FROM teacher_notes WHERE id = $1", [id]);
    },

    // ---------------- Student departments ----------------
    async getStudentDepartments(studentId, departmentId) {
      const rows = await many(
        `SELECT * FROM student_departments
         WHERE ($1::text IS NULL OR student_id = $1) AND ($2::text IS NULL OR department_id = $2)
         ORDER BY enrolled_at COLLATE "C" DESC, seq`,
        [studentId || null, departmentId || null],
      );
      return rows.map(toStudentDepartment);
    },
    async enrollStudentInDepartment(input) {
      await pool.query(
        `INSERT INTO student_departments (id, student_id, department_id, enrolled_at, enrolled_by)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (student_id, department_id) DO NOTHING`,
        [randomUUID(), input.studentId, input.departmentId, nowISO(), input.enrolledBy],
      );
      const row = await one(
        "SELECT * FROM student_departments WHERE student_id = $1 AND department_id = $2",
        [input.studentId, input.departmentId],
      );
      return toStudentDepartment(row!);
    },
    async unenrollStudentFromDepartment(studentId, departmentId) {
      await pool.query(
        "DELETE FROM student_departments WHERE student_id = $1 AND department_id = $2",
        [studentId, departmentId],
      );
    },
    async getStudentsByDepartment(departmentId) {
      const rows = await many(
        `SELECT u.* FROM users u
         WHERE u.role = 'student'
           AND EXISTS (SELECT 1 FROM student_departments sd
                       WHERE sd.student_id = u.id AND sd.department_id = $1)
         ORDER BY u.seq`,
        [departmentId],
      );
      return rows.map(toUser);
    },
    async getDepartmentsByStudent(studentId) {
      const rows = await many(
        `SELECT d.* FROM departments d
         WHERE EXISTS (SELECT 1 FROM student_departments sd
                       WHERE sd.department_id = d.id AND sd.student_id = $1)
         ORDER BY d.seq`,
        [studentId],
      );
      return rows.map(toDepartment);
    },
    async getStudentsByCourse(courseId) {
      const rows = await many(
        `SELECT u.* FROM users u
         JOIN courses c ON c.id = $1
         WHERE u.role = 'student' AND c.student_ids ? u.id
         ORDER BY u.seq`,
        [courseId],
      );
      return rows.map(toUser);
    },
  };
  return store;
}

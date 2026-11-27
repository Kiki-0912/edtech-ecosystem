// Admin console flows against a real Postgres engine (PGlite, in-process WASM)
// over a Unix socket: migrations 2 and 3, user and course changes, the cascades
// that the in-memory store mirrors (see admin.test.ts for the full contract).
import crypto from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import type { FastifyInstance, LightMyRequestResponse } from "fastify";
import type { AdminCourse, AdminUser, IntegrityRow, Overview } from "@edtech/shared";

const PASSWORD = "password123";
const ADMIN = "+15550001005";
const TEACHER = "+15550001001"; // u-teacher-1, teaches c-001
const STUDENT_1 = "+15550001002";
const STUDENT_3 = "+15550001004";

type Method = "GET" | "POST" | "PATCH" | "PUT" | "DELETE";
type Headers = { authorization: string };

let socketDir: string;
let pglite: PGlite;
let server: PGLiteSocketServer;
let app: FastifyInstance;
let adminHeaders: Headers;

/** Read the database directly (PGlite runs queries one at a time). */
async function sql<T = Record<string, unknown>>(query: string, params: unknown[] = []) {
  return (await pglite.query<T>(query, params)).rows;
}

async function count(query: string, params: unknown[] = []): Promise<number> {
  const [row] = await sql<{ n: number }>(`SELECT COUNT(*)::int AS n FROM ${query}`, params);
  return row.n;
}

const login = (payload: Record<string, string>) =>
  app.inject({ method: "POST", url: "/api/v1/auth/login", payload });

async function signIn(phone: string, password = PASSWORD): Promise<Headers> {
  const res = await login({ phone, password });
  assert.equal(res.statusCode, 200, res.body);
  return { authorization: `Bearer ${res.json().data.token}` };
}

const admin = (method: Method, url: string, payload?: object) =>
  app.inject({ method, url: `/api/v1/admin${url}`, headers: adminHeaders, payload });

function expectError(res: LightMyRequestResponse, status: number, code: string) {
  assert.equal(res.statusCode, status, res.body);
  assert.equal(res.json().error.code, code, res.body);
}

async function createUser(fields: Record<string, unknown>): Promise<AdminUser> {
  const res = await admin("POST", "/users", { password: "created-pass-1", ...fields });
  assert.equal(res.statusCode, 201, res.body);
  return res.json().data;
}

async function courseIdsOf(userId: string): Promise<string[]> {
  const [row] = await sql<{ course_ids: string[] }>("SELECT course_ids FROM users WHERE id = $1", [
    userId,
  ]);
  return row.course_ids;
}

async function membersOf(channelId: string): Promise<string[]> {
  const [row] = await sql<{ member_ids: string[] }>(
    "SELECT member_ids FROM chat_channels WHERE id = $1",
    [channelId],
  );
  return row.member_ids;
}

async function uploadPaste(as: Headers, studentId: string, assignmentId: string) {
  const key = crypto.randomBytes(32);
  const batch = {
    batchId: `b-${crypto.randomUUID()}`,
    studentId,
    assignmentId,
    createdAt: new Date().toISOString(),
    events: [
      {
        id: crypto.randomUUID(),
        sessionId: `s-${crypto.randomUUID()}`,
        assignmentId,
        studentId,
        type: "paste",
        occurredAt: new Date().toISOString(),
        payload: { characterCount: 900 },
      },
    ],
  };
  const res = await app.inject({
    method: "POST",
    url: "/api/v1/telemetry/batches",
    headers: as,
    payload: {
      ...batch,
      clientSignature: crypto
        .createHmac("sha256", key)
        .update(JSON.stringify(batch))
        .digest("base64url"),
      clientPublicKey: JSON.stringify({ kty: "oct", k: key.toString("base64url") }),
    },
  });
  assert.equal(res.statusCode, 202, res.body);
}

before(async () => {
  socketDir = await mkdtemp(path.join(tmpdir(), "edtech-admin-pg-"));
  pglite = await PGlite.create();
  server = new PGLiteSocketServer({
    db: pglite,
    path: path.join(socketDir, ".s.PGSQL.5432"),
    maxConnections: 4,
  });
  await server.start();

  // config.ts reads env at import time, so set it before importing the app.
  process.env.DATABASE_URL = `postgresql://postgres@/postgres?host=${socketDir}`;
  process.env.DATABASE_POOL_MAX = "1"; // PGlite is a single backend
  const { buildApp } = await import("../src/create-app");
  app = await buildApp();
  adminHeaders = await signIn(ADMIN);
});

after(async () => {
  await app?.close();
  await server?.stop();
  await pglite?.close();
  await rm(socketDir, { recursive: true, force: true });
});

describe("admin API on postgres", () => {
  test("migrations 2 and 3 add the account columns and the overview reports them", async () => {
    const versions = await sql<{ version: number }>(
      "SELECT version FROM schema_migrations ORDER BY version",
    );
    assert.deepEqual(
      versions.map((row) => row.version),
      [1, 2, 3, 4, 5],
    );
    const [column] = await sql<{ data_type: string; is_nullable: string; column_default: string }>(
      `SELECT data_type, is_nullable, column_default FROM information_schema.columns
       WHERE table_name = 'users' AND column_name = 'is_active'`,
    );
    assert.deepEqual(column, { data_type: "boolean", is_nullable: "NO", column_default: "true" });
    assert.equal(await count("users WHERE NOT is_active"), 0);
    const added = await sql<{ table_name: string; column_name: string; column_default: string }>(
      `SELECT table_name, column_name, column_default FROM information_schema.columns
       WHERE (table_name, column_name) IN (('users', 'token_version'),
                                           ('sms_verification_codes', 'attempts'))
         AND data_type = 'integer' AND is_nullable = 'NO'
       ORDER BY table_name`,
    );
    assert.deepEqual(added, [
      { table_name: "sms_verification_codes", column_name: "attempts", column_default: "0" },
      { table_name: "users", column_name: "token_version", column_default: "0" },
    ]);

    const res = await admin("GET", "/overview");
    assert.equal(res.statusCode, 200, res.body);
    const overview: Overview = res.json().data;
    assert.equal(overview.storage, "postgres");
    assert.equal(overview.database, "ok");
    assert.equal(overview.schemaVersion, 5);
    assert.deepEqual(overview.counts, {
      students: 4,
      teachers: 1,
      admins: 1,
      inactiveUsers: 0,
      courses: 1,
      departments: 18,
      assignments: 4,
      submissions: 3,
      telemetryBatches: 0,
      flaggedReports: 0,
    });
  });

  test("users are created, edited, disabled and re-enabled in the database", async () => {
    const phone = "+15556660001";
    const user = await createUser({
      displayName: "PG Teacher",
      email: "pg.teacher@example.edu",
      phone,
      role: "teacher",
    });
    assert.equal(user.isActive, true);
    assert.equal("passwordHash" in user, false);
    const [row] = await sql<{ role: string; is_active: boolean }>(
      "SELECT role, is_active FROM users WHERE id = $1",
      [user.id],
    );
    assert.deepEqual(row, { role: "teacher", is_active: true });

    expectError(
      await admin("POST", "/users", { displayName: "Dup", phone, role: "student", password: "long-enough" }),
      409,
      "USER_EXISTS",
    );
    expectError(
      await admin("PATCH", `/users/${user.id}`, { email: "tayyab@example.edu" }),
      409,
      "USER_EXISTS",
    );

    const renamed = await admin("PATCH", `/users/${user.id}`, { displayName: "PG Renamed" });
    assert.equal(renamed.json().data.displayName, "PG Renamed");
    const token = await signIn(phone, "created-pass-1");

    const disabled = await admin("PATCH", `/users/${user.id}`, { isActive: false });
    assert.equal(disabled.statusCode, 200, disabled.body);
    assert.equal(await count("users WHERE id = $1 AND NOT is_active", [user.id]), 1);
    expectError(await login({ phone, password: "created-pass-1" }), 403, "ACCOUNT_DISABLED");
    expectError(
      await app.inject({ method: "GET", url: "/api/v1/courses", headers: token }),
      401,
      "ACCOUNT_DISABLED",
    );
    const inactive = await admin("GET", "/users?status=inactive");
    assert.deepEqual(
      inactive.json().data.map((entry: AdminUser) => entry.id),
      [user.id],
    );

    await admin("PATCH", `/users/${user.id}`, { isActive: true });
    const reset = await admin("POST", `/users/${user.id}/password`, { password: "pg-new-pass-1" });
    assert.equal(reset.statusCode, 200, reset.body);
    assert.equal((await login({ phone, password: "pg-new-pass-1" })).statusCode, 200);

    expectError(
      await admin("PATCH", "/users/u-admin-1", { role: "teacher" }),
      409,
      "CANNOT_MODIFY_SELF",
    );
    expectError(
      await admin("PATCH", "/users/u-teacher-1", { role: "student" }),
      409,
      "USER_IN_USE",
    );
  });

  test("course create, teacher change and roster replace are stored with courseIds in sync", async () => {
    const other = await createUser({ displayName: "PG Other", phone: "+15556660002", role: "teacher" });
    expectError(
      await admin("POST", "/courses", { title: "X", code: "X", term: "X", teacherId: "u-student-3" }),
      400,
      "INVALID_TEACHER",
    );

    const created = await admin("POST", "/courses", {
      title: "Networks",
      code: "CS 330",
      term: "Spring 2027",
      teacherId: "u-teacher-1",
    });
    assert.equal(created.statusCode, 201, created.body);
    const course: AdminCourse = created.json().data;
    assert.equal(await count("courses WHERE id = $1", [course.id]), 1);
    assert.deepEqual(await courseIdsOf("u-teacher-1"), ["c-001", course.id]);

    const moved = await admin("PATCH", `/courses/${course.id}`, { teacherId: other.id, term: "Fall 2027" });
    assert.equal(moved.statusCode, 200, moved.body);
    assert.equal(moved.json().data.teacherName, "PG Other");
    assert.equal(moved.json().data.term, "Fall 2027");
    assert.deepEqual(await courseIdsOf("u-teacher-1"), ["c-001"]);
    assert.deepEqual(await courseIdsOf(other.id), [course.id]);
    expectError(await admin("PATCH", "/courses/nope", { title: "X" }), 404, "COURSE_NOT_FOUND");

    const put = (studentIds: string[], id = course.id) =>
      admin("PUT", `/courses/${id}/students`, { studentIds });
    expectError(await put(["u-student-2", "u-teacher-1"]), 400, "INVALID_STUDENT");
    const roster = await put(["u-student-2", "u-student-3", "u-student-2"]);
    assert.equal(roster.statusCode, 200, roster.body);
    assert.deepEqual(roster.json().data.studentIds, ["u-student-2", "u-student-3"]);
    const [stored] = await sql<{ student_ids: string[] }>(
      "SELECT student_ids FROM courses WHERE id = $1",
      [course.id],
    );
    assert.deepEqual(stored.student_ids, ["u-student-2", "u-student-3"]);
    assert.deepEqual(await courseIdsOf("u-student-2"), ["c-001", course.id]);
    await put(["u-student-3"]);
    assert.deepEqual(await courseIdsOf("u-student-2"), ["c-001"]);
    assert.deepEqual(await courseIdsOf("u-student-3"), ["c-001", course.id]);

    // c-001 has chat channels: membership follows the roster and the teacher.
    const seeded = (await admin("GET", "/courses")).json().data.find(
      (entry: AdminCourse) => entry.id === "c-001",
    ).studentIds as string[];
    await put(seeded.filter((id) => id !== "u-student-3"), "c-001");
    assert.ok(!(await membersOf("ch-001")).includes("u-student-3"));
    assert.ok(!(await courseIdsOf("u-student-3")).includes("c-001"));
    await put(seeded, "c-001");
    assert.ok((await membersOf("ch-001")).includes("u-student-3"));
    assert.ok((await courseIdsOf("u-student-3")).includes("c-001"));

    await admin("PATCH", "/courses/c-001", { teacherId: other.id });
    let members = await membersOf("ch-002");
    assert.ok(members.includes(other.id) && !members.includes("u-teacher-1"));
    await admin("PATCH", "/courses/c-001", { teacherId: "u-teacher-1" });
    members = await membersOf("ch-002");
    assert.ok(!members.includes(other.id) && members.includes("u-teacher-1"));
  });

  test("integrity rows join scores, flags, students and courses", async () => {
    await uploadPaste(await signIn(STUDENT_1), "u-student-1", "a-001");
    const res = await admin("GET", "/integrity?flagged=true");
    assert.equal(res.statusCode, 200, res.body);
    const rows: IntegrityRow[] = res.json().data;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].studentName, "Aeliya");
    assert.equal(rows[0].assignmentTitle, "Usability Study Report");
    assert.equal(rows[0].courseTitle, "Human-Computer Interaction");
    assert.ok(rows[0].flags.includes("large_paste"));
    const report = await app.inject({
      method: "GET",
      url: "/api/v1/integrity/a-001/u-student-1",
      headers: adminHeaders,
    });
    assert.equal(rows[0].score, report.json().data.effortScore.score);
    const overview = (await admin("GET", "/overview")).json().data as Overview;
    assert.equal(overview.counts.flaggedReports, 1);
    assert.equal(overview.counts.telemetryBatches, 1);
  });

  test("deleting a student removes their rows; a course teacher is in use", async () => {
    expectError(await admin("DELETE", "/users/u-teacher-1"), 409, "USER_IN_USE");
    // u-student-1 has a submission, attendance, a chat message, a department
    // enrollment and telemetry: make sure the checks below are meaningful.
    for (const table of [
      "submissions WHERE student_id = $1",
      "attendance_records WHERE student_id = $1",
      "chat_messages WHERE author_id = $1",
      "student_departments WHERE student_id = $1",
      "telemetry_batches WHERE student_id = $1",
      "effort_scores WHERE student_id = $1",
      "integrity_flags WHERE student_id = $1",
    ]) {
      assert.ok((await count(table, ["u-student-1"])) > 0, table);
    }

    const res = await admin("DELETE", "/users/u-student-1");
    assert.equal(res.statusCode, 200, res.body);
    for (const table of [
      "users WHERE id = $1",
      "submissions WHERE student_id = $1",
      "attendance_records WHERE student_id = $1",
      "chat_messages WHERE author_id = $1",
      "student_departments WHERE student_id = $1",
      "telemetry_batches WHERE student_id = $1",
      "effort_scores WHERE student_id = $1",
      "integrity_flags WHERE student_id = $1",
      "courses WHERE student_ids ? $1",
      "chat_channels WHERE member_ids ? $1",
    ]) {
      assert.equal(await count(table, ["u-student-1"]), 0, table);
    }
    expectError(await admin("DELETE", "/users/u-student-1"), 404, "USER_NOT_FOUND");
  });

  test("deleting a course cascades through every course table", async () => {
    const network = (await admin("GET", "/courses")).json().data.find(
      (entry: AdminCourse) => entry.title === "Networks",
    ) as AdminCourse;
    expectError(await admin("DELETE", `/users/${network.teacherId}`), 409, "USER_IN_USE");
    assert.equal((await admin("DELETE", `/courses/${network.id}`)).statusCode, 200);
    assert.equal(await count("users WHERE course_ids ? $1", [network.id]), 0);
    assert.equal((await admin("DELETE", `/users/${network.teacherId}`)).statusCode, 200);

    const event = await app.inject({
      method: "POST",
      url: "/api/v1/calendar",
      headers: adminHeaders,
      payload: { title: "Review", kind: "class", startsAt: "2026-12-02T10:00:00.000", courseId: "c-001" },
    });
    assert.equal(event.statusCode, 201, event.body);
    await uploadPaste(await signIn(STUDENT_3), "u-student-3", "a-002");
    assert.ok((await count("teacher_notes WHERE course_id = 'c-001'")) > 0);

    expectError(await admin("DELETE", "/courses/nope"), 404, "COURSE_NOT_FOUND");
    const res = await admin("DELETE", "/courses/c-001");
    assert.equal(res.statusCode, 200, res.body);

    for (const table of [
      "courses",
      "assignments",
      "submissions",
      "chat_channels",
      "chat_messages",
      "calendar_events WHERE course_id IS NOT NULL",
      "attendance_records",
      "teacher_notes",
      "telemetry_batches",
      "effort_scores",
      "integrity_flags",
      "users WHERE course_ids ? 'c-001'",
    ]) {
      assert.equal(await count(table), 0, table);
    }
    assert.equal(await count("calendar_events WHERE course_id IS NULL"), 1, "institution event stays");

    // Its teacher is no longer referenced by any course or note.
    assert.equal((await admin("DELETE", "/users/u-teacher-1")).statusCode, 200);
    const overview = (await admin("GET", "/overview")).json().data as Overview;
    assert.equal(overview.counts.courses, 0);
    assert.equal(overview.counts.assignments, 0);
    assert.equal(overview.counts.flaggedReports, 0);
  });
});

describe("auth hardening on postgres", () => {
  const get = (url: string, as: Headers) => app.inject({ method: "GET", url, headers: as });
  const tokenVersion = async (id: string) =>
    (await sql<{ token_version: number }>("SELECT token_version FROM users WHERE id = $1", [id]))[0]
      .token_version;

  test("password reset, role change and deactivation revoke tokens", async () => {
    const phone = "+15556660101";
    const user = await createUser({ displayName: "PG Admin 2", phone, role: "admin" });
    let token = await signIn(phone, "created-pass-1");
    assert.equal(await tokenVersion(user.id), 0);

    // A profile edit keeps the session.
    await admin("PATCH", `/users/${user.id}`, { displayName: "PG Admin Two" });
    assert.equal((await get("/api/v1/admin/overview", token)).statusCode, 200);

    await admin("POST", `/users/${user.id}/password`, { password: "pg-reset-pass-1" });
    assert.equal(await tokenVersion(user.id), 1);
    expectError(await get("/api/v1/admin/overview", token), 401, "SESSION_REVOKED");
    token = await signIn(phone, "pg-reset-pass-1");

    await admin("PATCH", `/users/${user.id}`, { isActive: false });
    await admin("PATCH", `/users/${user.id}`, { isActive: true });
    assert.equal(await tokenVersion(user.id), 2);
    expectError(await get("/api/v1/auth/me", token), 401, "SESSION_REVOKED");
    token = await signIn(phone, "pg-reset-pass-1");

    await admin("PATCH", `/users/${user.id}`, { role: "teacher" });
    assert.equal(await tokenVersion(user.id), 3);
    expectError(await get("/api/v1/courses", token), 401, "SESSION_REVOKED");
    assert.equal((await admin("DELETE", `/users/${user.id}`)).statusCode, 200);
  });

  test("two admins removing each other at once leave one active admin", async () => {
    const store = await import("../src/store/db");
    const makeAdmin = async (phone: string) => {
      const user = await createUser({ displayName: "PG Race", phone, role: "admin" });
      return { id: user.id, headers: await signIn(phone, "created-pass-1") };
    };
    const b = await makeAdmin("+15556660201");
    const c = await makeAdmin("+15556660202");
    await sql("UPDATE users SET is_active = FALSE WHERE id = 'u-admin-1'");
    try {
      const results = await Promise.all([
        app.inject({ method: "DELETE", url: `/api/v1/admin/users/${c.id}`, headers: b.headers }),
        app.inject({
          method: "PATCH",
          url: `/api/v1/admin/users/${b.id}`,
          headers: c.headers,
          payload: { role: "teacher" },
        }),
      ]);
      const body = results.map((res) => res.body).join("\n");
      assert.equal(results.filter((res) => res.statusCode === 200).length, 1, body);
      assert.equal(await count("users WHERE role = 'admin' AND is_active"), 1, body);

      // The store's guard on its own: the remaining admin cannot be removed.
      const [left] = await sql<{ id: string }>(
        "SELECT id FROM users WHERE role = 'admin' AND is_active",
      );
      const writes = await Promise.all([
        store.updateUser(left.id, { role: "student" }),
        store.updateUser(left.id, { isActive: false }),
        store.deleteUser(left.id),
      ]);
      assert.deepEqual(writes, ["last_admin", "last_admin", "last_admin"]);
      assert.equal(await count("users WHERE role = 'admin' AND is_active"), 1);
    } finally {
      await sql("UPDATE users SET is_active = TRUE WHERE id = 'u-admin-1'");
      await sql("DELETE FROM users WHERE id IN ($1, $2)", [b.id, c.id]);
      adminHeaders = await signIn(ADMIN);
    }
  });

  test("SMS codes: newest only, five guesses, five sends an hour, never for admins", async () => {
    process.env.SMS_DEV_ECHO = "true";
    try {
      const phone = "+15556660301";
      await createUser({ displayName: "PG SMS", phone, role: "student" });
      const send = () =>
        app.inject({ method: "POST", url: "/api/v1/auth/send-sms", payload: { phone } });
      const verify = (code: string) =>
        app.inject({ method: "POST", url: "/api/v1/auth/verify-sms", payload: { phone, code } });

      const first = (await send()).json().data.code as string;
      const second = (await send()).json().data.code as string;
      assert.equal(await count("sms_verification_codes WHERE phone = $1", [phone]), 2);
      if (first !== second) expectError(await verify(first), 400, "INVALID_CODE");
      for (let guess = 0; guess < 4; guess++) {
        const wrong = second === "999999" ? "100000" : String(Number(second) + 1);
        expectError(await verify(wrong), 400, "INVALID_CODE");
      }
      const [row] = await sql<{ attempts: number }>(
        "SELECT attempts FROM sms_verification_codes WHERE phone = $1 ORDER BY seq DESC LIMIT 1",
        [phone],
      );
      assert.equal(row.attempts, first !== second ? 5 : 4);
      if (first !== second) expectError(await verify(second), 400, "INVALID_CODE");

      const third = (await send()).json().data.code as string;
      assert.equal((await verify(third)).statusCode, 200);
      assert.equal(await count("sms_verification_codes WHERE phone = $1", [phone]), 0);

      for (let sent = 0; sent < 5; sent++) assert.equal((await send()).statusCode, 200);
      expectError(await send(), 429, "RATE_LIMITED");

      expectError(
        await app.inject({
          method: "POST",
          url: "/api/v1/auth/send-sms",
          payload: { phone: ADMIN },
        }),
        403,
        "SMS_SIGN_IN_DISABLED",
      );
    } finally {
      delete process.env.SMS_DEV_ECHO;
    }
  });
});

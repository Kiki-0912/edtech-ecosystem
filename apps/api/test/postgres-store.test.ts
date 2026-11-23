// Runs the API against a real Postgres engine (PGlite, in-process WASM) over a
// Unix socket, so the `pg` driver, SQL and migrations are exercised without a
// network port or an external database server.
import crypto from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import type { FastifyInstance } from "fastify";

const TEACHER = "+15550001001";
const ADMIN = "+15550001005";

let socketDir: string;
let pglite: PGlite;
let server: PGLiteSocketServer;
let buildApp: () => Promise<FastifyInstance>;
let app: FastifyInstance;

async function login(target: FastifyInstance, phone: string, password = "password123") {
  const res = await target.inject({
    method: "POST",
    url: "/api/v1/auth/login",
    payload: { phone, password },
  });
  assert.equal(res.statusCode, 200, res.body);
  return { authorization: `Bearer ${res.json().data.token}` };
}

/** Close the current app (and its pool) and start a fresh one on the same DB. */
async function restartApp() {
  await app.close();
  app = await buildApp();
}

before(async () => {
  socketDir = await mkdtemp(path.join(tmpdir(), "edtech-pg-"));
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
  ({ buildApp } = await import("../src/create-app"));
  app = await buildApp();
});

after(async () => {
  await app?.close();
  await server?.stop();
  await pglite?.close();
  await rm(socketDir, { recursive: true, force: true });
});

describe("postgres store", () => {
  test("health reports the postgres store", async () => {
    const res = await app.inject({ method: "GET", url: "/health" });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().storage, "postgres");
    assert.equal(res.json().database, "ok");
  });

  test("migrations are recorded once and re-running them is a no-op", async () => {
    const { runMigrations, createPool } = await import("../src/store/pg-store");
    const pool = createPool(process.env.DATABASE_URL!);
    try {
      assert.deepEqual(await runMigrations(pool), []);
      const { rows } = await pool.query("SELECT version FROM schema_migrations");
      assert.deepEqual(
        rows.map((row) => row.version).sort(),
        [1, 2, 3],
      );
    } finally {
      await pool.end();
    }
  });

  test("an empty database is seeded with reference and demo data", async () => {
    const headers = await login(app, TEACHER);
    const college = await app.inject({ method: "GET", url: "/api/v1/college", headers });
    assert.equal(college.statusCode, 200);
    assert.equal(college.json().data.departmentCount, 18);
    // Flyer order is kept (insertion order, not alphabetical).
    assert.equal(college.json().data.departments[0].code, "ARC");

    const courses = await app.inject({ method: "GET", url: "/api/v1/courses", headers });
    assert.equal(courses.json().data.length, 1);
  });

  test("data survives an app restart and seeding does not run twice", async () => {
    const register = await app.inject({
      method: "POST",
      url: "/api/v1/auth/register",
      payload: { phone: "+15557770001", password: "secret123", display_name: "Persisted" },
    });
    assert.equal(register.statusCode, 201, register.body);

    const headers = await login(app, ADMIN);
    const note = await app.inject({
      method: "POST",
      url: "/api/v1/notes",
      headers,
      payload: {
        courseId: "c-001",
        bookName: "Clean Code",
        courseCode: "CIT-301",
        title: "Persisted note",
        content: "Written before restart",
      },
    });
    assert.equal(note.statusCode, 201, note.body);

    await restartApp();

    await login(app, "+15557770001", "secret123");
    const notes = await app.inject({
      method: "GET",
      url: "/api/v1/notes?courseId=c-001",
      headers: await login(app, ADMIN),
    });
    const titles = notes.json().data.map((n: { title: string }) => n.title);
    assert.ok(titles.includes("Persisted note"));
    assert.equal(titles.length, 3); // 2 seeded + 1 created: no re-seed duplicates
  });

  test("duplicate phone registration is rejected", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/auth/register",
      payload: { phone: TEACHER, password: "secret123" },
    });
    assert.equal(res.statusCode, 409);
  });

  test("calendar times round-trip exactly as the client sent them", async () => {
    const headers = await login(app, ADMIN);
    const created = await app.inject({
      method: "POST",
      url: "/api/v1/calendar",
      headers,
      payload: {
        title: "Local-time exam",
        kind: "quiz",
        startsAt: "2026-12-01T09:30:00.000",
        endsAt: "2026-12-01T11:00:00.000",
        departmentId: "dept-cit",
      },
    });
    assert.equal(created.statusCode, 201, created.body);
    assert.equal(created.json().data.startsAt, "2026-12-01T09:30:00.000");

    const list = await app.inject({
      method: "GET",
      url: "/api/v1/calendar?departmentId=dept-cit",
      headers,
    });
    const event = list
      .json()
      .data.find((e: { title: string }) => e.title === "Local-time exam");
    assert.equal(event.startsAt, "2026-12-01T09:30:00.000");
    assert.equal(event.endsAt, "2026-12-01T11:00:00.000");
  });

  test("attendance for the same student and date is updated, not duplicated", async () => {
    const headers = await login(app, TEACHER);
    const mark = (status: string) =>
      app.inject({
        method: "POST",
        url: "/api/v1/attendance",
        headers,
        payload: { courseId: "c-001", studentId: "u-student-1", date: "2026-10-10", status },
      });
    const first = await mark("absent");
    const second = await mark("late");
    assert.equal(first.statusCode, 201, first.body);
    assert.equal(second.json().data.id, first.json().data.id);
    assert.equal(second.json().data.status, "late");

    const records = await app.inject({
      method: "GET",
      url: "/api/v1/attendance?courseId=c-001&date=2026-10-10",
      headers,
    });
    assert.equal(records.json().data.length, 1);
  });

  test("a reference to a missing record is a 400, not a 500", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/attendance",
      headers: await login(app, TEACHER),
      payload: { courseId: "no-such-course", studentId: "u-student-1", date: "2026-10-11", status: "present" },
    });
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error.code, "INVALID_REFERENCE");
  });

  test("department enrollment is idempotent and course membership persists", async () => {
    const headers = await login(app, ADMIN);
    for (let i = 0; i < 2; i++) {
      const res = await app.inject({
        method: "POST",
        url: "/api/v1/students/u-student-3/departments",
        headers,
        payload: { departmentId: "dept-mec" },
      });
      assert.equal(res.statusCode, 201, res.body);
    }
    const students = await app.inject({
      method: "GET",
      url: "/api/v1/departments/dept-mec/students",
      headers,
    });
    assert.deepEqual(
      students.json().data.map((s: { id: string }) => s.id),
      ["u-student-3"],
    );

    const roster = await app.inject({
      method: "GET",
      url: "/api/v1/courses/c-001/students",
      headers,
    });
    assert.ok(roster.json().data.length > 0);
  });

  test("a retried telemetry batch is accepted once and enables replay", async () => {
    const key = crypto.randomBytes(32);
    const batch = {
      batchId: `b-${crypto.randomUUID()}`,
      studentId: "u-student-1",
      assignmentId: "a-001",
      createdAt: new Date().toISOString(),
      events: [
        {
          id: "e-1",
          sessionId: "s-pg-1",
          assignmentId: "a-001",
          studentId: "u-student-1",
          type: "keystroke",
          occurredAt: new Date().toISOString(),
          payload: { intervalMs: 120 },
        },
      ],
    };
    const clientSignature = crypto
      .createHmac("sha256", key)
      .update(JSON.stringify(batch))
      .digest("base64url");
    const payload = {
      ...batch,
      clientSignature,
      clientPublicKey: JSON.stringify({ kty: "oct", k: key.toString("base64url") }),
    };
    const headers = await login(app, "+15550001002");

    for (let i = 0; i < 2; i++) {
      const res = await app.inject({
        method: "POST",
        url: "/api/v1/telemetry/batches",
        headers,
        payload,
      });
      assert.equal(res.statusCode, 202, res.body);
    }

    const report = await app.inject({
      method: "GET",
      url: "/api/v1/integrity/a-001/u-student-1",
      headers: await login(app, TEACHER),
    });
    assert.equal(report.statusCode, 200, report.body);
    assert.equal(report.json().data.replayAvailable, true);
    assert.equal(report.json().data.effortScore.sessionId, "s-pg-1");
  });
});

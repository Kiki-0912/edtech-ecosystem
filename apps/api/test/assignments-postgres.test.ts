// Assignment create/update/delete on Postgres (PGlite over a Unix socket):
// migration 5, calendar sync and cascades must match the in-memory store.
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import type { FastifyInstance } from "fastify";

const TEACHER = "+15550001001"; // u-teacher-1, teaches c-001
const STUDENT = "+15550001002"; // u-student-1, enrolled in c-001
const DUE = "2026-12-15T17:00:00";

let socketDir: string;
let pglite: PGlite;
let server: PGLiteSocketServer;
let app: FastifyInstance;
let store: typeof import("../src/store/db");
const headers: Record<"teacher" | "student", { authorization: string }> = {} as never;

async function login(phone: string) {
  const res = await app.inject({
    method: "POST",
    url: "/api/v1/auth/login",
    payload: { phone, password: "password123" },
  });
  assert.equal(res.statusCode, 200, res.body);
  return { authorization: `Bearer ${res.json().data.token}` };
}

const sql = async <T = Record<string, unknown>>(query: string, params: unknown[] = []) =>
  (await pglite.query<T>(query, params)).rows;

async function linkedEvents(assignmentId: string) {
  return sql<{ id: string; title: string; starts_at: string; course_id: string; kind: string }>(
    "SELECT * FROM calendar_events WHERE assignment_id = $1",
    [assignmentId],
  );
}

before(async () => {
  socketDir = await mkdtemp(path.join(tmpdir(), "edtech-assign-pg-"));
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
  store = await import("../src/store/db");
  app = await buildApp();
  headers.teacher = await login(TEACHER);
  headers.student = await login(STUDENT);
});

after(async () => {
  await app?.close();
  await server?.stop();
  await pglite?.close();
  await rm(socketDir, { recursive: true, force: true });
});

describe("assignments on postgres", () => {
  test("migration 5 adds calendar_events.assignment_id with a cascading FK and an index", async () => {
    assert.equal(store.storeKind(), "postgres");
    const [column] = await sql<{ data_type: string; is_nullable: string }>(
      `SELECT data_type, is_nullable FROM information_schema.columns
       WHERE table_name = 'calendar_events' AND column_name = 'assignment_id'`,
    );
    assert.deepEqual(column, { data_type: "text", is_nullable: "YES" });
    const [fk] = await sql<{ delete_rule: string }>(
      `SELECT rc.delete_rule FROM information_schema.referential_constraints rc
       JOIN information_schema.key_column_usage k ON k.constraint_name = rc.constraint_name
       WHERE k.table_name = 'calendar_events' AND k.column_name = 'assignment_id'`,
    );
    assert.equal(fk?.delete_rule, "CASCADE");
    const indexes = await sql<{ indexname: string }>(
      "SELECT indexname FROM pg_indexes WHERE tablename = 'calendar_events'",
    );
    assert.ok(indexes.some((row) => row.indexname === "idx_calendar_assignment"));
    // Seeded events are not linked.
    const linked = await sql("SELECT id FROM calendar_events WHERE assignment_id IS NOT NULL");
    assert.deepEqual(linked, []);
  });

  test("create, update and draft keep one calendar event in sync", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/courses/c-001/assignments",
      headers: headers.teacher,
      payload: { title: "  PG essay ", dueAt: DUE },
    });
    assert.equal(res.statusCode, 201, res.body);
    const created = res.json().data;
    assert.equal(created.title, "PG essay");
    assert.equal(created.brief, "");
    assert.equal(created.status, "open");
    assert.equal(created.dueAt, DUE);

    let events = await linkedEvents(created.id);
    assert.equal(events.length, 1);
    assert.equal(events[0]!.title, "PG essay due");
    assert.equal(events[0]!.starts_at, DUE);
    assert.equal(events[0]!.kind, "assignment");
    assert.equal(events[0]!.course_id, "c-001");
    const eventId = events[0]!.id;

    const calendar = await app.inject({ method: "GET", url: "/api/v1/calendar", headers: headers.student });
    const mine = (calendar.json().data as { id: string; assignmentId: string | null }[]).find(
      (event) => event.id === eventId,
    );
    assert.equal(mine?.assignmentId, created.id);

    const newDue = "2027-01-10T09:30:00";
    const patch = await app.inject({
      method: "PATCH",
      url: `/api/v1/assignments/${created.id}`,
      headers: headers.teacher,
      payload: { title: "PG final", dueAt: newDue },
    });
    assert.equal(patch.statusCode, 200, patch.body);
    assert.equal(patch.json().data.dueAt, newDue);
    events = await linkedEvents(created.id);
    assert.equal(events.length, 1);
    assert.equal(events[0]!.id, eventId);
    assert.equal(events[0]!.title, "PG final due");
    assert.equal(events[0]!.starts_at, newDue);

    const put = await app.inject({
      method: "PUT",
      url: `/api/v1/calendar/${eventId}`,
      headers: headers.teacher,
      payload: { title: "Moved" },
    });
    assert.equal(put.statusCode, 409);
    assert.equal(put.json().error.code, "ASSIGNMENT_EVENT");

    await app.inject({
      method: "PATCH",
      url: `/api/v1/assignments/${created.id}`,
      headers: headers.teacher,
      payload: { status: "draft" },
    });
    assert.equal((await linkedEvents(created.id)).length, 0);
    const hidden = await app.inject({
      method: "GET",
      url: `/api/v1/assignments/${created.id}`,
      headers: headers.student,
    });
    assert.equal(hidden.statusCode, 404);

    await app.inject({
      method: "PATCH",
      url: `/api/v1/assignments/${created.id}`,
      headers: headers.teacher,
      payload: { status: "closed" },
    });
    assert.equal((await linkedEvents(created.id)).length, 1);
    const closed = await app.inject({
      method: "POST",
      url: `/api/v1/assignments/${created.id}/submissions`,
      headers: headers.student,
      payload: { attachments: [] },
    });
    assert.equal(closed.statusCode, 409);
    assert.equal(closed.json().error.code, "ASSIGNMENT_CLOSED");

    const draft = await app.inject({
      method: "POST",
      url: "/api/v1/courses/c-001/assignments",
      headers: headers.teacher,
      payload: { title: "PG draft", dueAt: DUE, status: "draft", brief: "Later" },
    });
    assert.equal(draft.statusCode, 201, draft.body);
    assert.equal((await linkedEvents(draft.json().data.id)).length, 0);
  });

  test("delete cascades submissions, telemetry, effort scores, flags and the event", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/courses/c-001/assignments",
      headers: headers.teacher,
      payload: { title: "PG cascade", dueAt: DUE },
    });
    const id = res.json().data.id as string;
    const submit = await app.inject({
      method: "POST",
      url: `/api/v1/assignments/${id}/submissions`,
      headers: headers.student,
      payload: { attachments: [] },
    });
    assert.equal(submit.statusCode, 201, submit.body);
    await store.createTelemetryBatch({
      batchId: "pg-batch-cascade",
      studentId: "u-student-1",
      assignmentId: id,
      events: [],
      clientSignature: "sig",
      clientPublicKey: "key",
      createdAt: DUE,
    });
    await store.setEffortScore({
      sessionId: "u-student-1:pg-sess",
      assignmentId: id,
      studentId: "u-student-1",
      score: 75,
      keystrokes: 5,
      pastes: 0,
      pasteVolume: 0,
      aiTabSwitches: 0,
      activeSeconds: 30,
      computedAt: DUE,
    });
    await store.setIntegrityFlags("u-student-1", id, ["large_paste"]);

    const count = async (table: string) =>
      Number(
        (await sql<{ n: number }>(`SELECT COUNT(*)::int AS n FROM ${table} WHERE assignment_id = $1`, [id]))[0]!.n,
      );
    for (const table of ["submissions", "telemetry_batches", "effort_scores", "integrity_flags", "calendar_events"]) {
      assert.equal(await count(table), 1, table);
    }

    const del = await app.inject({
      method: "DELETE",
      url: `/api/v1/assignments/${id}`,
      headers: headers.teacher,
    });
    assert.equal(del.statusCode, 200, del.body);
    assert.deepEqual(del.json(), { data: { success: true } });

    for (const table of ["submissions", "telemetry_batches", "effort_scores", "integrity_flags", "calendar_events"]) {
      assert.equal(await count(table), 0, table);
    }
    assert.equal((await sql("SELECT id FROM assignments WHERE id = $1", [id])).length, 0);
    // Seeded data is untouched.
    assert.ok((await sql("SELECT id FROM submissions WHERE assignment_id = 'a-001'")).length > 0);

    const again = await app.inject({
      method: "DELETE",
      url: `/api/v1/assignments/${id}`,
      headers: headers.teacher,
    });
    assert.equal(again.statusCode, 404);
  });
});

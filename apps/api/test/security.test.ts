import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/create-app";

// Seeded accounts (see apps/api/src/store/memory.ts); password123 for all.
const TEACHER = "+15550001001";
const STUDENT = "+15550001002"; // u-student-1
const ADMIN = "+15550001005";

let app: FastifyInstance;
const tokens: Record<string, string> = {};

async function login(phone: string): Promise<string> {
  const res = await app.inject({
    method: "POST",
    url: "/api/v1/auth/login",
    payload: { phone, password: "password123" },
  });
  assert.equal(res.statusCode, 200, res.body);
  return res.json().data.token;
}

const auth = (who: string) => ({ authorization: `Bearer ${tokens[who]}` });

before(async () => {
  app = await buildApp();
  tokens.teacher = await login(TEACHER);
  tokens.student = await login(STUDENT);
  tokens.admin = await login(ADMIN);
});

after(async () => {
  await app.close();
});

describe("health and auth", () => {
  test("health is public", async () => {
    const res = await app.inject({ method: "GET", url: "/health" });
    assert.equal(res.statusCode, 200);
  });

  test("protected routes need a token", async () => {
    const res = await app.inject({ method: "GET", url: "/api/v1/courses" });
    assert.equal(res.statusCode, 401);
    assert.equal(res.json().error.code, "UNAUTHORIZED");
  });

  test("college is served under /api/v1", async () => {
    const res = await app.inject({
      method: "GET",
      url: "/api/v1/college",
      headers: auth("student"),
    });
    assert.equal(res.statusCode, 200);
  });

  test("self sign-up cannot create admins", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/auth/register",
      payload: {
        phone: "+15559990001",
        email: "x@example.edu",
        displayName: "X",
        password: "secret123",
        role: "admin",
      },
    });
    assert.equal(res.statusCode, 400);
  });
});

describe("no impersonation", () => {
  test("chat messages are authored by the caller, not the body", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/channels/ch-002/messages",
      headers: auth("student"),
      payload: { authorId: "u-teacher-1", body: "pretending" },
    });
    assert.equal(res.statusCode, 201, res.body);
    assert.equal(res.json().data.authorId, "u-student-1");
  });

  test("students cannot post announcements even by spoofing authorId", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/channels/ch-001/messages",
      headers: auth("student"),
      payload: { authorId: "u-teacher-1", body: "fake announcement" },
    });
    assert.equal(res.statusCode, 403);
  });

  test("students cannot submit as another student", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/assignments/a-001/submissions",
      headers: auth("student"),
      payload: { studentId: "u-student-2", attachments: [] },
    });
    assert.equal(res.statusCode, 403);
  });

  test("students can submit their own work without passing studentId", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/assignments/a-001/submissions",
      headers: auth("student"),
      payload: { attachments: [] },
    });
    assert.ok([200, 201].includes(res.statusCode), res.body);
    assert.equal(res.json().data.studentId, "u-student-1");
  });
});

describe("role guards", () => {
  const studentForbidden: [string, string, object?][] = [
    ["POST", "/api/v1/attendance", { courseId: "c-001", studentId: "u-student-1", date: "2026-11-20", status: "present" }],
    ["POST", "/api/v1/attendance/bulk", { courseId: "c-001", date: "2026-11-20", records: [] }],
    ["POST", "/api/v1/notes", { courseId: "c-001", bookName: "", courseCode: "CS", title: "t", content: "c" }],
    ["GET", "/api/v1/excel/export/attendance"],
    ["GET", "/api/v1/excel/export/notes"],
  ];

  for (const [method, url, payload] of studentForbidden) {
    test(`students get 403 on ${method} ${url}`, async () => {
      const res = await app.inject({
        method: method as "GET" | "POST",
        url,
        headers: auth("student"),
        payload,
      });
      assert.equal(res.statusCode, 403, res.body);
      assert.equal(res.json().error.code, "FORBIDDEN");
    });
  }

  test("students list only classmates' names; staff get full records", async () => {
    // u-student-4 is enrolled in c-001 with u-student-1 (memory.ts seed).
    const classmates = await app.inject({
      method: "GET",
      url: "/api/v1/students",
      headers: auth("student"),
    });
    assert.equal(classmates.statusCode, 200, classmates.body);
    const rows: Record<string, unknown>[] = classmates.json().data;
    assert.ok(rows.some((row) => row.id === "u-student-1"));
    assert.ok(rows.some((row) => row.id === "u-student-4"));
    for (const row of rows) {
      assert.deepEqual(Object.keys(row).sort(), ["displayName", "id", "role"]);
    }

    for (const who of ["teacher", "admin"]) {
      const staff = await app.inject({ method: "GET", url: "/api/v1/students", headers: auth(who) });
      assert.equal(staff.statusCode, 200, staff.body);
      assert.ok(staff.json().data.every((row: { phone?: string }) => "phone" in row), who);
    }

    // A student who shares no course with anyone sees only themself.
    const loner = await app.inject({
      method: "POST",
      url: "/api/v1/auth/register",
      payload: { email: "loner@example.edu", password: "loner-pass", display_name: "Loner" },
    });
    assert.equal(loner.statusCode, 201, loner.body);
    const own = await app.inject({
      method: "GET",
      url: "/api/v1/students",
      headers: { authorization: `Bearer ${loner.json().data.token}` },
    });
    assert.deepEqual(
      own.json().data.map((row: { id: string }) => row.id),
      [loner.json().data.user.id],
    );
  });

  test("students can read only their own student record", async () => {
    const other = await app.inject({
      method: "GET",
      url: "/api/v1/students/u-student-4",
      headers: auth("student"),
    });
    assert.equal(other.statusCode, 403, other.body);
    assert.equal(other.json().error.code, "FORBIDDEN");
    const own = await app.inject({
      method: "GET",
      url: "/api/v1/students/u-student-1",
      headers: auth("student"),
    });
    assert.equal(own.statusCode, 200, own.body);
    const staff = await app.inject({
      method: "GET",
      url: "/api/v1/students/u-student-4",
      headers: auth("teacher"),
    });
    assert.equal(staff.statusCode, 200, staff.body);
  });

  test("teachers can mark attendance", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/attendance/bulk",
      headers: auth("teacher"),
      payload: {
        courseId: "c-001",
        date: "2026-11-20",
        records: [{ studentId: "u-student-1", status: "late" }],
      },
    });
    assert.equal(res.statusCode, 201, res.body);
  });

  test("admins can export notes", async () => {
    const res = await app.inject({
      method: "GET",
      url: "/api/v1/excel/export/notes",
      headers: auth("admin"),
    });
    assert.equal(res.statusCode, 200);
    assert.ok(Array.isArray(res.json().data.headers));
  });
});

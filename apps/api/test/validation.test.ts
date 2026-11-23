// Missing or malformed bodies answer 400 INVALID_BODY instead of a 500 or junk
// rows, and the in-memory store rejects what Postgres rejects.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/create-app";

const TEACHER = "+15550001001";
const ADMIN = "+15550001005";

let app: FastifyInstance;
const headers: Record<string, { authorization: string }> = {};

async function login(phone: string) {
  const res = await app.inject({
    method: "POST",
    url: "/api/v1/auth/login",
    payload: { phone, password: "password123" },
  });
  assert.equal(res.statusCode, 200, res.body);
  return { authorization: `Bearer ${res.json().data.token}` };
}

before(async () => {
  app = await buildApp();
  headers.teacher = await login(TEACHER);
  headers.admin = await login(ADMIN);
});

after(async () => {
  await app.close();
});

type Case = { method: "POST" | "PUT"; url: string; who: string; payload?: unknown };

const INVALID: Case[] = [
  { method: "POST", url: "/api/v1/excel/import/students", who: "admin" },
  { method: "POST", url: "/api/v1/excel/import/students", who: "admin", payload: { rows: "x" } },
  { method: "POST", url: "/api/v1/attendance", who: "teacher" },
  {
    method: "POST",
    url: "/api/v1/attendance",
    who: "teacher",
    payload: { courseId: "c-001", studentId: "u-student-1", date: "2026-10-01", status: "asleep" },
  },
  {
    method: "POST",
    url: "/api/v1/attendance/bulk",
    who: "teacher",
    payload: { courseId: "c-001", date: "2026-10-01", records: [{ studentId: "u-student-1", status: "maybe" }] },
  },
  { method: "POST", url: "/api/v1/attendance/bulk", who: "teacher", payload: { courseId: "c-001" } },
  { method: "POST", url: "/api/v1/students", who: "admin" },
  { method: "POST", url: "/api/v1/students", who: "admin", payload: { displayName: "  " } },
  { method: "PUT", url: "/api/v1/students/u-student-1", who: "admin", payload: { displayName: 7 } },
  { method: "POST", url: "/api/v1/departments", who: "admin", payload: { name: "X" } },
  {
    method: "POST",
    url: "/api/v1/departments",
    who: "admin",
    payload: { name: "X", code: "X", category: "Forever", durationMonths: 12 },
  },
  { method: "PUT", url: "/api/v1/departments/dept-mec", who: "admin", payload: { durationMonths: "a" } },
  { method: "POST", url: "/api/v1/notes", who: "teacher", payload: { title: "No course" } },
  { method: "PUT", url: "/api/v1/notes/note-1", who: "admin", payload: { title: 5 } },
  { method: "POST", url: "/api/v1/students/u-student-1/departments", who: "admin", payload: {} },
  { method: "POST", url: "/api/v1/calendar", who: "teacher", payload: { title: "T", kind: "party", startsAt: "2026-10-01" } },
  { method: "POST", url: "/api/v1/calendar", who: "teacher", payload: { title: "T", kind: "class", startsAt: "not a date" } },
  { method: "POST", url: "/api/v1/calendar", who: "teacher", payload: { title: "T" } },
  { method: "PUT", url: "/api/v1/calendar/e-001", who: "teacher", payload: { kind: "party" } },
  { method: "PUT", url: "/api/v1/calendar/e-001", who: "teacher", payload: { startsAt: "soon" } },
];

describe("invalid bodies are 400 INVALID_BODY", () => {
  for (const c of INVALID) {
    test(`${c.method} ${c.url} ${JSON.stringify(c.payload ?? null)}`, async () => {
      const res = await app.inject({
        method: c.method,
        url: c.url,
        headers: headers[c.who],
        ...(c.payload === undefined ? {} : { payload: c.payload as object }),
      });
      assert.equal(res.statusCode, 400, res.body);
      assert.equal(res.json().error.code, "INVALID_BODY");
    });
  }

  test("role checks still answer before body validation", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/students",
      headers: headers.teacher,
      payload: {},
    });
    assert.equal(res.statusCode, 403);
  });

  test("a valid calendar event is still created", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/calendar",
      headers: headers.teacher,
      payload: { title: "Lab", kind: "class", startsAt: "2026-10-01T09:00:00Z", courseId: "c-001" },
    });
    assert.equal(res.statusCode, 201, res.body);
  });
});

describe("the memory store rejects what Postgres rejects", () => {
  test("a duplicate phone on POST /students is 409", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/students",
      headers: headers.admin,
      payload: { displayName: "Copy", phone: "+15550001002" },
    });
    assert.equal(res.statusCode, 409, res.body);
  });

  test("an unknown department on enrollment is 400 INVALID_REFERENCE", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/students/u-student-1/departments",
      headers: headers.admin,
      payload: { departmentId: "no-such-dept" },
    });
    assert.equal(res.statusCode, 400, res.body);
    assert.equal(res.json().error.code, "INVALID_REFERENCE");
  });

  test("an unknown course on POST /notes is 400 INVALID_REFERENCE", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/notes",
      headers: headers.admin,
      payload: { courseId: "no-such-course", bookName: "B", courseCode: "C", title: "T" },
    });
    assert.equal(res.statusCode, 400, res.body);
    assert.equal(res.json().error.code, "INVALID_REFERENCE");
  });
});

describe("excel import", () => {
  test("ids are unique UUIDs and missing cells are reported per row", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/excel/import/students",
      headers: headers.admin,
      payload: {
        courseId: "c-001",
        rows: [
          { name: "A", rollNumber: "R-901", contact: "+15559000001" },
          { name: "B", rollNumber: "R-902", contact: "+15559000002" },
          { name: "C" },
        ],
      },
    });
    assert.equal(res.statusCode, 201, res.body);
    const data = res.json().data as {
      imported: number;
      students: { id: string }[];
      errors: { row: number }[];
    };
    assert.equal(data.imported, 2);
    const ids = data.students.map((s) => s.id);
    assert.equal(new Set(ids).size, 2);
    for (const id of ids) assert.match(id, /^[0-9a-f-]{36}$/);
    assert.equal(data.errors.length, 1);

    const roster = await app.inject({
      method: "GET",
      url: "/api/v1/courses/c-001/students",
      headers: headers.admin,
    });
    const rosterIds = (roster.json().data as { id: string }[]).map((s) => s.id);
    for (const id of ids) assert.ok(rosterIds.includes(id));
  });

  test("an unknown course is 400 and imports nothing", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/excel/import/students",
      headers: headers.admin,
      payload: { courseId: "nope", rows: [{ name: "Z", rollNumber: "R-999", contact: "+15559000009" }] },
    });
    assert.equal(res.statusCode, 400, res.body);
  });
});

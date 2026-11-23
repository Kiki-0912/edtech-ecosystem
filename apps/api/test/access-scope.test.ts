// Reads and writes are scoped to the caller: students see only their own data,
// teachers only the courses they teach, admins everything.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/create-app";

// Seeded accounts (see apps/api/src/store/memory.ts); password123 for all.
const TEACHER = "+15550001001"; // u-teacher-1, teaches c-001
const STUDENT = "+15550001002"; // u-student-1, enrolled in c-001
const ADMIN = "+15550001005";
const OTHER_TEACHER = "+15559990001"; // created below, teaches OTHER_COURSE

let app: FastifyInstance;
let otherCourseId: string;
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
  headers.student = await login(STUDENT);
  headers.admin = await login(ADMIN);

  const teacher = await app.inject({
    method: "POST",
    url: "/api/v1/admin/users",
    headers: headers.admin,
    payload: {
      displayName: "Other Teacher",
      phone: OTHER_TEACHER,
      role: "teacher",
      password: "password123",
    },
  });
  assert.equal(teacher.statusCode, 201, teacher.body);
  const course = await app.inject({
    method: "POST",
    url: "/api/v1/admin/courses",
    headers: headers.admin,
    payload: { title: "Other", code: "OTH-1", term: "T1", teacherId: teacher.json().data.id },
  });
  assert.equal(course.statusCode, 201, course.body);
  otherCourseId = course.json().data.id;
  headers.otherTeacher = await login(OTHER_TEACHER);
});

after(async () => {
  await app.close();
});

const get = (url: string, who: string) => app.inject({ method: "GET", url, headers: headers[who] });

describe("students", () => {
  test("a student can read only their own record", async () => {
    assert.equal((await get("/api/v1/students/u-student-1", "student")).statusCode, 200);
    assert.equal((await get("/api/v1/students/u-student-2", "student")).statusCode, 403);
    assert.equal((await get("/api/v1/students/u-student-2", "teacher")).statusCode, 200);
  });
});

describe("attendance reads", () => {
  test("a student sees only their own attendance records", async () => {
    const res = await get("/api/v1/attendance?courseId=c-001", "student");
    assert.equal(res.statusCode, 200);
    const records = res.json().data as { studentId: string }[];
    assert.ok(records.length > 0);
    assert.ok(records.every((r) => r.studentId === "u-student-1"));
  });

  test("a student cannot read another student's record by id", async () => {
    assert.equal((await get("/api/v1/attendance/att-r-2", "student")).statusCode, 403);
    assert.equal((await get("/api/v1/attendance/att-r-1", "student")).statusCode, 200);
  });

  test("a teacher sees only courses they teach", async () => {
    assert.equal((await get("/api/v1/attendance?courseId=c-001", "otherTeacher")).statusCode, 403);
    const all = await get("/api/v1/attendance", "otherTeacher");
    assert.equal(all.statusCode, 200);
    assert.deepEqual(all.json().data, []);
    assert.equal((await get("/api/v1/attendance/att-r-2", "otherTeacher")).statusCode, 403);
    assert.equal((await get("/api/v1/attendance/att-r-2", "teacher")).statusCode, 200);
    assert.equal((await get("/api/v1/attendance/att-r-2", "admin")).statusCode, 200);
  });

  test("the course roster: a student gets only their own row", async () => {
    const url = "/api/v1/attendance/course/c-001/students";
    const mine = await get(url, "student");
    assert.equal(mine.statusCode, 200);
    assert.deepEqual(
      (mine.json().data as { id: string }[]).map((s) => s.id),
      ["u-student-1"],
    );
    assert.equal((await get(url, "otherTeacher")).statusCode, 403);
    assert.equal((await get(url, "teacher")).json().data.length, 4);
    assert.equal((await get(url, "admin")).statusCode, 200);
  });
});

describe("attendance writes", () => {
  const record = { courseId: "c-001", studentId: "u-student-1", date: "2026-10-01", status: "late" };

  test("a teacher cannot mark a course they do not teach", async () => {
    const single = await app.inject({
      method: "POST",
      url: "/api/v1/attendance",
      headers: headers.otherTeacher,
      payload: record,
    });
    assert.equal(single.statusCode, 403);
    const bulk = await app.inject({
      method: "POST",
      url: "/api/v1/attendance/bulk",
      headers: headers.otherTeacher,
      payload: { courseId: "c-001", date: "2026-10-01", records: [{ studentId: "u-student-1", status: "present" }] },
    });
    assert.equal(bulk.statusCode, 403);
  });

  test("the course's teacher and admins can mark it", async () => {
    for (const who of ["teacher", "admin"]) {
      const res = await app.inject({
        method: "POST",
        url: "/api/v1/attendance",
        headers: headers[who],
        payload: record,
      });
      assert.equal(res.statusCode, 201, res.body);
    }
  });
});

describe("assignment roster", () => {
  test("only staff who manage the course can view it", async () => {
    assert.equal((await get("/api/v1/assignments/a-001/roster", "student")).statusCode, 403);
    assert.equal((await get("/api/v1/assignments/a-001/roster", "otherTeacher")).statusCode, 403);
    assert.equal((await get("/api/v1/assignments/a-001/roster", "teacher")).statusCode, 200);
    assert.equal((await get("/api/v1/assignments/a-001/roster", "admin")).statusCode, 200);
  });
});

describe("channel messages", () => {
  test("reading is members-only", async () => {
    assert.equal((await get("/api/v1/channels/ch-001/messages", "student")).statusCode, 200);
    const outsider = await get("/api/v1/channels/ch-001/messages", "otherTeacher");
    assert.equal(outsider.statusCode, 403);
    assert.equal(outsider.json().error.code, "NOT_A_MEMBER");
  });
});

describe("calendar", () => {
  test("a non-admin's userId query is ignored", async () => {
    const res = await get("/api/v1/calendar?userId=u-teacher-1", "otherTeacher");
    assert.equal(res.statusCode, 200);
    const events = res.json().data as { courseId: string | null }[];
    assert.ok(events.every((event) => event.courseId !== "c-001"));
  });

  test("admins can still view another user's calendar", async () => {
    const res = await get("/api/v1/calendar?userId=u-teacher-1", "admin");
    const events = res.json().data as { courseId: string | null }[];
    assert.ok(events.some((event) => event.courseId === "c-001"));
  });

  test("a teacher cannot edit or delete another course's events", async () => {
    const put = await app.inject({
      method: "PUT",
      url: "/api/v1/calendar/e-001",
      headers: headers.otherTeacher,
      payload: { title: "Hijacked" },
    });
    assert.equal(put.statusCode, 403);
    const del = await app.inject({
      method: "DELETE",
      url: "/api/v1/calendar/e-001",
      headers: headers.otherTeacher,
    });
    assert.equal(del.statusCode, 403);
  });

  test("a teacher cannot move their event into a course they do not teach", async () => {
    const res = await app.inject({
      method: "PUT",
      url: "/api/v1/calendar/e-002",
      headers: headers.teacher,
      payload: { courseId: otherCourseId },
    });
    assert.equal(res.statusCode, 403);
  });

  test("the course's teacher can edit and delete its events", async () => {
    const put = await app.inject({
      method: "PUT",
      url: "/api/v1/calendar/e-002",
      headers: headers.teacher,
      payload: { title: "Renamed" },
    });
    assert.equal(put.statusCode, 200, put.body);
    assert.equal(put.json().data.title, "Renamed");
    const del = await app.inject({
      method: "DELETE",
      url: "/api/v1/calendar/e-003",
      headers: headers.teacher,
    });
    assert.equal(del.statusCode, 200, del.body);
  });

  test("institution events (no course) are created and managed by admins only", async () => {
    const event = { title: "Open day", kind: "institution", startsAt: "2026-12-05T09:00:00Z" };
    // A teacher could otherwise create an event they cannot edit or delete.
    for (const payload of [event, { ...event, courseId: null }]) {
      const res = await app.inject({
        method: "POST",
        url: "/api/v1/calendar",
        headers: headers.teacher,
        payload,
      });
      assert.equal(res.statusCode, 403, res.body);
      assert.equal(res.json().error.code, "FORBIDDEN");
    }
    const put = await app.inject({
      method: "PUT",
      url: "/api/v1/calendar/e-005",
      headers: headers.teacher,
      payload: { title: "Renamed" },
    });
    assert.equal(put.statusCode, 403);

    const created = await app.inject({
      method: "POST",
      url: "/api/v1/calendar",
      headers: headers.admin,
      payload: event,
    });
    assert.equal(created.statusCode, 201, created.body);
    const id = created.json().data.id as string;
    const edited = await app.inject({
      method: "PUT",
      url: `/api/v1/calendar/${id}`,
      headers: headers.admin,
      payload: { title: "Open day (moved)" },
    });
    assert.equal(edited.statusCode, 200, edited.body);
  });

  test("a teacher's event in their own course stays editable by them", async () => {
    const created = await app.inject({
      method: "POST",
      url: "/api/v1/calendar",
      headers: headers.teacher,
      payload: { title: "Lab", kind: "class", startsAt: "2026-12-06T09:00:00Z", courseId: "c-001" },
    });
    assert.equal(created.statusCode, 201, created.body);
    const put = await app.inject({
      method: "PUT",
      url: `/api/v1/calendar/${created.json().data.id}`,
      headers: headers.teacher,
      payload: { title: "Lab (moved)" },
    });
    assert.equal(put.statusCode, 200, put.body);
  });
});

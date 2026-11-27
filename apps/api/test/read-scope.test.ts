// Course, roster, notes, department and export reads are scoped to the caller:
// students see their own courses and classmates' names only, teachers see only
// the courses they teach, admins everything.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/create-app";

// Seeded accounts (see apps/api/src/store/memory.ts); password123 for all.
const TEACHER = "+15550001001"; // u-teacher-1, teaches c-001
const STUDENT = "+15550001002"; // u-student-1, enrolled in c-001
const CLASSMATE = "+15550001003"; // u-student-2, enrolled in c-001
const ADMIN = "+15550001005";
const OTHER_TEACHER = "+15559990002"; // created below, teaches an empty course

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
  headers.student = await login(STUDENT);
  headers.classmate = await login(CLASSMATE);
  headers.admin = await login(ADMIN);

  const teacher = await app.inject({
    method: "POST",
    url: "/api/v1/admin/users",
    headers: headers.admin,
    payload: { displayName: "Elsewhere", phone: OTHER_TEACHER, role: "teacher", password: "password123" },
  });
  assert.equal(teacher.statusCode, 201, teacher.body);
  const course = await app.inject({
    method: "POST",
    url: "/api/v1/admin/courses",
    headers: headers.admin,
    payload: { title: "Elsewhere", code: "ELS-1", term: "T1", teacherId: teacher.json().data.id },
  });
  assert.equal(course.statusCode, 201, course.body);
  headers.otherTeacher = await login(OTHER_TEACHER);
});

after(async () => {
  await app.close();
});

const get = (url: string, who: string) => app.inject({ method: "GET", url, headers: headers[who] });
const post = (url: string, who: string, payload: object) =>
  app.inject({ method: "POST", url, headers: headers[who], payload });
const data = async (url: string, who: string) => {
  const res = await get(url, who);
  assert.equal(res.statusCode, 200, res.body);
  return res.json().data;
};

const SUMMARY_KEYS = ["displayName", "id", "role"];

describe("courses", () => {
  test("the catalogue shows enrolment only to the course's staff", async () => {
    const find = (list: { id: string }[]) => list.find((c) => c.id === "c-001") as {
      studentIds: string[];
      studentCount: number;
    };
    const asStudent = find(await data("/api/v1/courses", "student"));
    assert.deepEqual(asStudent.studentIds, ["u-student-1"]);
    assert.equal(asStudent.studentCount, 4);
    assert.deepEqual(find(await data("/api/v1/courses", "otherTeacher")).studentIds, []);
    assert.equal(find(await data("/api/v1/courses", "teacher")).studentIds.length, 4);
  });

  test("course detail hides contact details from classmates", async () => {
    const asStudent = await data("/api/v1/courses/c-001", "student");
    for (const person of [...asStudent.roster, asStudent.teacher]) {
      assert.deepEqual(Object.keys(person).sort(), SUMMARY_KEYS);
    }
    const asTeacher = await data("/api/v1/courses/c-001", "teacher");
    assert.ok(asTeacher.roster.every((u: { phone?: string }) => typeof u.phone === "string"));
    assert.equal((await get("/api/v1/courses/c-001", "otherTeacher")).statusCode, 403);
  });

  test("assignments and channels are for the course's own people", async () => {
    for (const url of [
      "/api/v1/courses/c-001/assignments",
      "/api/v1/assignments/a-001",
      "/api/v1/courses/c-001/channels",
    ]) {
      assert.equal((await get(url, "student")).statusCode, 200, url);
      assert.equal((await get(url, "teacher")).statusCode, 200, url);
      assert.equal((await get(url, "otherTeacher")).statusCode, 403, url);
    }
  });

  test("course students: full for staff, names for classmates, refused otherwise", async () => {
    const asStudent = await data("/api/v1/courses/c-001/students", "student");
    assert.equal(asStudent.length, 4);
    for (const person of asStudent) assert.deepEqual(Object.keys(person).sort(), SUMMARY_KEYS);
    const asTeacher = await data("/api/v1/courses/c-001/students", "teacher");
    assert.ok(asTeacher.every((u: { email?: string }) => typeof u.email === "string"));
    assert.equal((await get("/api/v1/courses/c-001/students", "otherTeacher")).statusCode, 403);
  });

  test("teachers submit only for students on courses they teach", async () => {
    const res = await post("/api/v1/assignments/a-002/submissions", "otherTeacher", {
      studentId: "u-student-2",
      attachments: [],
    });
    assert.equal(res.statusCode, 403, res.body);
  });
});

describe("students and departments", () => {
  test("teachers see only the students on their rosters", async () => {
    assert.deepEqual(await data("/api/v1/students", "otherTeacher"), []);
    assert.equal((await data("/api/v1/students", "teacher")).length, 4);
    assert.equal((await get("/api/v1/students/u-student-2", "otherTeacher")).statusCode, 403);
  });

  test("department rosters are admin-only", async () => {
    const [department] = await data("/api/v1/departments", "admin");
    const url = `/api/v1/departments/${department.id}/students`;
    assert.equal((await get(url, "admin")).statusCode, 200);
    assert.equal((await get(url, "teacher")).statusCode, 403);
    assert.equal((await get(url, "student")).statusCode, 403);
  });

  test("a student's departments: themselves, their teachers and admins", async () => {
    const url = "/api/v1/students/u-student-1/departments";
    for (const who of ["student", "teacher", "admin"]) {
      assert.equal((await get(url, who)).statusCode, 200, who);
    }
    assert.equal((await get(url, "classmate")).statusCode, 403);
    assert.equal((await get(url, "otherTeacher")).statusCode, 403);
  });
});

describe("notes", () => {
  const NOTE = { courseId: "c-001", bookName: "B", courseCode: "CS 301", title: "Scoped", content: "" };

  test("notes are written only for taught courses and read only by the course", async () => {
    assert.equal((await post("/api/v1/notes", "otherTeacher", NOTE)).statusCode, 403);
    const created = await post("/api/v1/notes", "teacher", NOTE);
    assert.equal(created.statusCode, 201, created.body);
    const id = created.json().data.id;

    assert.ok((await data("/api/v1/notes", "student")).some((n: { id: string }) => n.id === id));
    assert.ok(!(await data("/api/v1/notes", "otherTeacher")).some((n: { id: string }) => n.id === id));
    assert.equal((await get(`/api/v1/notes/${id}`, "student")).statusCode, 200);
    assert.equal((await get(`/api/v1/notes/${id}`, "otherTeacher")).statusCode, 403);
  });
});

describe("exports", () => {
  test("teachers export only their own courses", async () => {
    for (const kind of ["students", "attendance", "notes"]) {
      const scoped = `/api/v1/excel/export/${kind}?courseId=c-001`;
      assert.equal((await get(scoped, "otherTeacher")).statusCode, 403, kind);
      assert.equal((await get(scoped, "teacher")).statusCode, 200, kind);
      const all = await data(`/api/v1/excel/export/${kind}`, "otherTeacher");
      assert.deepEqual(all.rows, [], kind);
    }
  });
});

describe("attendance writes", () => {
  test("only students on the course roster can be marked", async () => {
    const single = await post("/api/v1/attendance", "teacher", {
      courseId: "c-001",
      studentId: "u-admin-1",
      date: "2026-11-20",
      status: "present",
    });
    assert.equal(single.statusCode, 400, single.body);
    assert.equal(single.json().error.code, "INVALID_REFERENCE");

    const bulk = await post("/api/v1/attendance/bulk", "teacher", {
      courseId: "c-001",
      date: "2026-11-20",
      records: [
        { studentId: "u-student-1", status: "present" },
        { studentId: "u-admin-1", status: "present" },
      ],
    });
    assert.equal(bulk.statusCode, 400, bulk.body);
    assert.equal(bulk.json().error.code, "INVALID_REFERENCE");

    const ok = await post("/api/v1/attendance", "teacher", {
      courseId: "c-001",
      studentId: "u-student-1",
      date: "2026-11-20",
      status: "present",
    });
    assert.equal(ok.statusCode, 201, ok.body);
  });
});

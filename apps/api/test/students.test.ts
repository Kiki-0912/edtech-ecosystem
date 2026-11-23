// /students create/update/delete keep users, course rosters and related rows
// consistent, and answer 404/400 instead of writing junk.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/create-app";

const ADMIN = "+15550001005";

let app: FastifyInstance;
let admin: { authorization: string };
let otherCourseId: string;

before(async () => {
  app = await buildApp();
  const res = await app.inject({
    method: "POST",
    url: "/api/v1/auth/login",
    payload: { phone: ADMIN, password: "password123" },
  });
  assert.equal(res.statusCode, 200, res.body);
  admin = { authorization: `Bearer ${res.json().data.token}` };
  const course = await app.inject({
    method: "POST",
    url: "/api/v1/admin/courses",
    headers: admin,
    payload: { title: "Second", code: "SEC-1", term: "T1", teacherId: "u-teacher-1" },
  });
  assert.equal(course.statusCode, 201, course.body);
  otherCourseId = course.json().data.id;
});

after(async () => {
  await app.close();
});

const call = (method: "GET" | "POST" | "PUT" | "DELETE", url: string, payload?: object) =>
  app.inject({ method, url, headers: admin, ...(payload ? { payload } : {}) });

async function rosterIds(courseId: string): Promise<string[]> {
  const res = await call("GET", `/api/v1/courses/${courseId}/students`);
  return (res.json().data as { id: string }[]).map((s) => s.id);
}

async function createStudent(phone: string, courseId?: string): Promise<string> {
  const res = await call("POST", "/api/v1/students", { displayName: "New", phone, courseId });
  assert.equal(res.statusCode, 201, res.body);
  return res.json().data.id;
}

describe("PUT /students/:id", () => {
  test("an unknown student is 404", async () => {
    const res = await call("PUT", "/api/v1/students/no-such-id", { displayName: "X" });
    assert.equal(res.statusCode, 404);
    assert.ok(res.json().error.code);
  });

  test("an unknown course is 400 and keeps existing enrollments", async () => {
    const id = await createStudent("+15558880001", "c-001");
    const res = await call("PUT", `/api/v1/students/${id}`, { courseId: "no-such-course" });
    assert.equal(res.statusCode, 400);
    assert.ok((await rosterIds("c-001")).includes(id));
    const user = await call("GET", `/api/v1/students/${id}`);
    assert.deepEqual(user.json().data.courseIds, ["c-001"]);
  });

  test("moving course keeps users.courseIds in sync with the rosters", async () => {
    const id = await createStudent("+15558880002", "c-001");
    const res = await call("PUT", `/api/v1/students/${id}`, { courseId: otherCourseId });
    assert.equal(res.statusCode, 200, res.body);
    assert.deepEqual(res.json().data.courseIds, [otherCourseId]);
    assert.ok(!(await rosterIds("c-001")).includes(id));
    assert.ok((await rosterIds(otherCourseId)).includes(id));
  });

  test("a duplicate phone is 409", async () => {
    const id = await createStudent("+15558880003");
    const res = await call("PUT", `/api/v1/students/${id}`, { phone: "+15550001002" });
    assert.equal(res.statusCode, 409, res.body);
  });
});

describe("POST /students", () => {
  test("a new student in a course appears on its roster with matching courseIds", async () => {
    const id = await createStudent("+15558880004", "c-001");
    const user = await call("GET", `/api/v1/students/${id}`);
    assert.deepEqual(user.json().data.courseIds, ["c-001"]);
    assert.ok((await rosterIds("c-001")).includes(id));
  });

  test("an unknown course is 400 and creates nobody", async () => {
    const res = await call("POST", "/api/v1/students", {
      displayName: "Ghost",
      phone: "+15558880005",
      courseId: "no-such-course",
    });
    assert.equal(res.statusCode, 400);
    const all = await call("GET", "/api/v1/students");
    assert.ok(!(all.json().data as { phone: string }[]).some((s) => s.phone === "+15558880005"));
  });
});

describe("DELETE /students/:id", () => {
  test("actually deletes the student and their roster entries", async () => {
    const id = await createStudent("+15558880006", "c-001");
    const res = await call("DELETE", `/api/v1/students/${id}`);
    assert.equal(res.statusCode, 200, res.body);
    assert.equal((await call("GET", `/api/v1/students/${id}`)).statusCode, 404);
    assert.ok(!(await rosterIds("c-001")).includes(id));
    // The phone is free again once the account is gone.
    await createStudent("+15558880006");
  });

  test("an unknown or non-student id is 404", async () => {
    assert.equal((await call("DELETE", "/api/v1/students/no-such-id")).statusCode, 404);
    assert.equal((await call("DELETE", "/api/v1/students/u-teacher-1")).statusCode, 404);
  });
});

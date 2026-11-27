// Teachers create, edit and delete assignments (in-memory store): permissions,
// validation, draft hiding, closed submissions, calendar sync and cascades.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/create-app";
import {
  createTelemetryBatch,
  getCalendarEvents,
  getEffortScore,
  getIntegrityFlags,
  getSubmissionsByAssignment,
  getTelemetryBatchesFor,
  setEffortScore,
  setIntegrityFlags,
} from "../src/store/db";

// Seeded accounts (see apps/api/src/store/memory.ts); password123 for all.
const TEACHER = "+15550001001"; // u-teacher-1, teaches c-001
const STUDENT = "+15550001002"; // u-student-1, enrolled in c-001
const ADMIN = "+15550001005";
const OTHER_TEACHER = "+15559990011"; // created below, teaches otherCourseId

let app: FastifyInstance;
let otherCourseId: string;
const headers: Record<string, { authorization: string }> = {};

type Who = "teacher" | "student" | "admin" | "otherTeacher" | "anonymous";

async function login(phone: string) {
  const res = await app.inject({
    method: "POST",
    url: "/api/v1/auth/login",
    payload: { phone, password: "password123" },
  });
  assert.equal(res.statusCode, 200, res.body);
  return { authorization: `Bearer ${res.json().data.token}` };
}

function call(method: "GET" | "POST" | "PATCH" | "PUT" | "DELETE", url: string, who: Who, payload?: object) {
  return app.inject({
    method,
    url: `/api/v1${url}`,
    headers: who === "anonymous" ? {} : headers[who],
    ...(payload === undefined ? {} : { payload }),
  });
}

async function create(payload: object, who: Who = "teacher", courseId = "c-001") {
  const res = await call("POST", `/courses/${courseId}/assignments`, who, payload);
  assert.equal(res.statusCode, 201, res.body);
  return res.json().data as {
    id: string;
    courseId: string;
    title: string;
    brief: string;
    dueAt: string;
    status: string;
    createdAt: string;
  };
}

/** The calendar events linked to an assignment (straight from the store). */
async function linkedEvents(assignmentId: string) {
  const all = await getCalendarEvents(new Set(["c-001", otherCourseId]));
  return all.filter((event) => event.assignmentId === assignmentId);
}

const DUE = "2026-12-15T17:00:00"; // client local time, no zone: must round-trip unchanged

before(async () => {
  app = await buildApp();
  headers.teacher = await login(TEACHER);
  headers.student = await login(STUDENT);
  headers.admin = await login(ADMIN);

  const teacher = await call("POST", "/admin/users", "admin", {
    displayName: "Other Teacher",
    phone: OTHER_TEACHER,
    role: "teacher",
    password: "password123",
  });
  assert.equal(teacher.statusCode, 201, teacher.body);
  const course = await call("POST", "/admin/courses", "admin", {
    title: "Other",
    code: "OTH-1",
    term: "T1",
    teacherId: teacher.json().data.id,
  });
  assert.equal(course.statusCode, 201, course.body);
  otherCourseId = course.json().data.id;
  headers.otherTeacher = await login(OTHER_TEACHER);
});

after(async () => {
  await app.close();
});

describe("POST /courses/:courseId/assignments", () => {
  test("the course's teacher creates an assignment with defaults", async () => {
    const res = await call("POST", "/courses/c-001/assignments", "teacher", {
      title: "  Lab report  ",
      dueAt: DUE,
    });
    assert.equal(res.statusCode, 201, res.body);
    const data = res.json().data;
    assert.equal(data.title, "Lab report");
    assert.equal(data.brief, "");
    assert.equal(data.status, "open");
    assert.equal(data.dueAt, DUE);
    assert.equal(data.courseId, "c-001");
    assert.ok(data.id && data.createdAt);

    const read = await call("GET", `/assignments/${data.id}`, "student");
    assert.equal(read.statusCode, 200);
    assert.equal(read.json().data.assignment.dueAt, DUE);
  });

  test("an admin may create in any course", async () => {
    const created = await create({ title: "Admin made", dueAt: DUE, brief: "b" }, "admin", otherCourseId);
    assert.equal(created.courseId, otherCourseId);
    assert.equal(created.brief, "b");
  });

  test("another teacher, a student and an anonymous caller cannot", async () => {
    const payload = { title: "Nope", dueAt: DUE };
    const other = await call("POST", "/courses/c-001/assignments", "otherTeacher", payload);
    assert.equal(other.statusCode, 403);
    assert.equal(other.json().error.code, "FORBIDDEN");
    const student = await call("POST", "/courses/c-001/assignments", "student", payload);
    assert.equal(student.statusCode, 403);
    assert.equal(student.json().error.code, "FORBIDDEN");
    // Students get 403 even for a course that doesn't exist.
    const studentMissing = await call("POST", "/courses/nope/assignments", "student", payload);
    assert.equal(studentMissing.statusCode, 403);
    const anon = await call("POST", "/courses/c-001/assignments", "anonymous", payload);
    assert.equal(anon.statusCode, 401);
  });

  test("an unknown course is 404 COURSE_NOT_FOUND", async () => {
    const res = await call("POST", "/courses/nope/assignments", "teacher", { title: "x", dueAt: DUE });
    assert.equal(res.statusCode, 404);
    assert.equal(res.json().error.code, "COURSE_NOT_FOUND");
  });

  test("invalid bodies are 400 INVALID_BODY", async () => {
    const bad: object[] = [
      {},
      { dueAt: DUE },
      { title: "x" },
      { title: "", dueAt: DUE },
      { title: "   ", dueAt: DUE },
      { title: "x".repeat(201), dueAt: DUE },
      { title: 42, dueAt: DUE },
      { title: "x", dueAt: "not a date" },
      { title: "x", dueAt: "" },
      { title: "x", dueAt: DUE, brief: "b".repeat(10_001) },
      { title: "x", dueAt: DUE, brief: 5 },
      { title: "x", dueAt: DUE, status: "archived" },
    ];
    for (const payload of bad) {
      const res = await call("POST", "/courses/c-001/assignments", "teacher", payload);
      assert.equal(res.statusCode, 400, `${JSON.stringify(payload)} -> ${res.body}`);
      assert.equal(res.json().error.code, "INVALID_BODY");
    }
    // Boundaries are accepted.
    await create({ title: "x".repeat(200), dueAt: DUE, brief: "b".repeat(10_000) });
  });
});

describe("PATCH /assignments/:assignmentId", () => {
  test("the course's teacher and an admin can edit", async () => {
    const created = await create({ title: "Edit me", dueAt: DUE });
    const res = await call("PATCH", `/assignments/${created.id}`, "teacher", {
      title: "  Edited  ",
      brief: "New brief",
    });
    assert.equal(res.statusCode, 200, res.body);
    assert.equal(res.json().data.title, "Edited");
    assert.equal(res.json().data.brief, "New brief");
    assert.equal(res.json().data.dueAt, DUE);
    assert.equal(res.json().data.createdAt, created.createdAt);

    const admin = await call("PATCH", `/assignments/${created.id}`, "admin", { status: "closed" });
    assert.equal(admin.statusCode, 200, admin.body);
    assert.equal(admin.json().data.status, "closed");
    assert.equal(admin.json().data.title, "Edited");
  });

  test("other teachers, students and anonymous callers cannot", async () => {
    const created = await create({ title: "Guarded", dueAt: DUE });
    for (const who of ["otherTeacher", "student"] as const) {
      const res = await call("PATCH", `/assignments/${created.id}`, who, { title: "Hacked" });
      assert.equal(res.statusCode, 403, who);
      assert.equal(res.json().error.code, "FORBIDDEN");
    }
    assert.equal((await call("PATCH", `/assignments/${created.id}`, "anonymous", { title: "x" })).statusCode, 401);
    const read = await call("GET", `/assignments/${created.id}`, "teacher");
    assert.equal(read.json().data.assignment.title, "Guarded");
  });

  test("unknown assignment is 404, bad bodies are 400", async () => {
    const missing = await call("PATCH", "/assignments/nope", "teacher", { title: "x" });
    assert.equal(missing.statusCode, 404);
    assert.equal(missing.json().error.code, "ASSIGNMENT_NOT_FOUND");

    const created = await create({ title: "Valid", dueAt: DUE });
    const bad: object[] = [
      {},
      { unknown: 1 },
      { title: "" },
      { title: "  " },
      { title: "x".repeat(201) },
      { dueAt: "tomorrow-ish" },
      { brief: "b".repeat(10_001) },
      { status: "archived" },
      { title: null },
    ];
    for (const payload of bad) {
      const res = await call("PATCH", `/assignments/${created.id}`, "teacher", payload);
      assert.equal(res.statusCode, 400, `${JSON.stringify(payload)} -> ${res.body}`);
      assert.equal(res.json().error.code, "INVALID_BODY");
    }
  });
});

describe("DELETE /assignments/:assignmentId", () => {
  test("permissions and 404", async () => {
    const created = await create({ title: "Delete guard", dueAt: DUE });
    for (const who of ["otherTeacher", "student"] as const) {
      const res = await call("DELETE", `/assignments/${created.id}`, who);
      assert.equal(res.statusCode, 403, who);
      assert.equal(res.json().error.code, "FORBIDDEN");
    }
    assert.equal((await call("DELETE", `/assignments/${created.id}`, "anonymous")).statusCode, 401);

    const res = await call("DELETE", `/assignments/${created.id}`, "teacher");
    assert.equal(res.statusCode, 200, res.body);
    assert.deepEqual(res.json(), { data: { success: true } });
    assert.equal((await call("GET", `/assignments/${created.id}`, "teacher")).statusCode, 404);

    const again = await call("DELETE", `/assignments/${created.id}`, "teacher");
    assert.equal(again.statusCode, 404);
    assert.equal(again.json().error.code, "ASSIGNMENT_NOT_FOUND");

    const byAdmin = await create({ title: "Admin deletes", dueAt: DUE });
    assert.equal((await call("DELETE", `/assignments/${byAdmin.id}`, "admin")).statusCode, 200);
  });

  test("cascades submissions, telemetry, effort scores, flags and the calendar event", async () => {
    const created = await create({ title: "Cascade", dueAt: DUE });
    const submit = await call("POST", `/assignments/${created.id}/submissions`, "student", {
      attachments: [],
    });
    assert.equal(submit.statusCode, 201, submit.body);
    await createTelemetryBatch({
      batchId: "batch-cascade",
      studentId: "u-student-1",
      assignmentId: created.id,
      events: [],
      clientSignature: "sig",
      clientPublicKey: "key",
      createdAt: DUE,
    });
    await setEffortScore({
      sessionId: "u-student-1:sess-cascade",
      assignmentId: created.id,
      studentId: "u-student-1",
      score: 80,
      keystrokes: 10,
      pastes: 0,
      pasteVolume: 0,
      aiTabSwitches: 0,
      activeSeconds: 60,
      computedAt: DUE,
    });
    await setIntegrityFlags("u-student-1", created.id, ["large_paste"]);
    assert.equal((await linkedEvents(created.id)).length, 1);

    const res = await call("DELETE", `/assignments/${created.id}`, "teacher");
    assert.equal(res.statusCode, 200, res.body);

    assert.deepEqual(await getSubmissionsByAssignment(created.id), []);
    assert.deepEqual(await getTelemetryBatchesFor("u-student-1", created.id), []);
    assert.equal(await getEffortScore("u-student-1", created.id), undefined);
    assert.deepEqual(await getIntegrityFlags("u-student-1", created.id), []);
    assert.deepEqual(await linkedEvents(created.id), []);
    // Other assignments' data is untouched.
    assert.ok((await getSubmissionsByAssignment("a-001")).length > 0);
  });
});

describe("drafts", () => {
  test("are hidden from students and other teachers, visible to managers", async () => {
    const draft = await create({ title: "Secret draft", dueAt: DUE, status: "draft" });
    const ids = (body: { data: { id: string }[] }) => body.data.map((a) => a.id);

    // Course assignment list.
    assert.ok(!ids((await call("GET", "/courses/c-001/assignments", "student")).json()).includes(draft.id));
    assert.ok(!ids((await call("GET", "/courses/c-001/assignments", "otherTeacher")).json()).includes(draft.id));
    assert.ok(ids((await call("GET", "/courses/c-001/assignments", "teacher")).json()).includes(draft.id));
    assert.ok(ids((await call("GET", "/courses/c-001/assignments", "admin")).json()).includes(draft.id));

    // Course detail.
    const detailIds = (who: Who) =>
      call("GET", "/courses/c-001", who).then((res) =>
        (res.json().data.assignments as { id: string }[]).map((a) => a.id),
      );
    assert.ok(!(await detailIds("student")).includes(draft.id));
    assert.ok((await detailIds("teacher")).includes(draft.id));
    assert.ok((await detailIds("admin")).includes(draft.id));

    // Single assignment.
    const studentRead = await call("GET", `/assignments/${draft.id}`, "student");
    assert.equal(studentRead.statusCode, 404);
    assert.equal(studentRead.json().error.code, "ASSIGNMENT_NOT_FOUND");
    assert.equal((await call("GET", `/assignments/${draft.id}`, "otherTeacher")).statusCode, 404);
    assert.equal((await call("GET", `/assignments/${draft.id}`, "teacher")).statusCode, 200);
    assert.equal((await call("GET", `/assignments/${draft.id}`, "admin")).statusCode, 200);

    // Course list counts only open assignments.
    const courses = (await call("GET", "/courses", "student")).json().data as {
      id: string;
      openAssignmentCount: number;
    }[];
    const before = courses.find((c) => c.id === "c-001")!.openAssignmentCount;
    await call("PATCH", `/assignments/${draft.id}`, "teacher", { status: "open" });
    const afterOpen = (await call("GET", "/courses", "student")).json().data as typeof courses;
    assert.equal(afterOpen.find((c) => c.id === "c-001")!.openAssignmentCount, before + 1);

    // Once published the student sees it.
    assert.equal((await call("GET", `/assignments/${draft.id}`, "student")).statusCode, 200);
  });

  test("still reject submissions with 409 ASSIGNMENT_DRAFT", async () => {
    const draft = await create({ title: "Draft submit", dueAt: DUE, status: "draft" });
    const res = await call("POST", `/assignments/${draft.id}/submissions`, "student", { attachments: [] });
    assert.equal(res.statusCode, 409);
    assert.equal(res.json().error.code, "ASSIGNMENT_DRAFT");
  });
});

describe("closed assignments", () => {
  test("reject submissions with 409 ASSIGNMENT_CLOSED", async () => {
    const created = await create({ title: "Closing", dueAt: DUE });
    const open = await call("POST", `/assignments/${created.id}/submissions`, "student", { attachments: [] });
    assert.equal(open.statusCode, 201, open.body);

    await call("PATCH", `/assignments/${created.id}`, "teacher", { status: "closed" });
    const res = await call("POST", `/assignments/${created.id}/submissions`, "student", { attachments: [] });
    assert.equal(res.statusCode, 409);
    assert.equal(res.json().error.code, "ASSIGNMENT_CLOSED");

    // The seeded closed assignment too.
    const seeded = await call("POST", "/assignments/a-004/submissions", "student", { attachments: [] });
    assert.equal(seeded.statusCode, 409);
    assert.equal(seeded.json().error.code, "ASSIGNMENT_CLOSED");
  });
});

describe("calendar sync", () => {
  test("an open assignment gets exactly one deadline event", async () => {
    const created = await create({ title: "Essay", dueAt: DUE });
    const events = await linkedEvents(created.id);
    assert.equal(events.length, 1);
    const { id, ...rest } = events[0]!;
    assert.ok(id);
    assert.deepEqual(rest, {
      courseId: "c-001",
      departmentId: null,
      assignmentId: created.id,
      title: "Essay due",
      kind: "assignment",
      startsAt: DUE,
      endsAt: null,
    });

    // Students see it on their calendar.
    const calendar = await call("GET", "/calendar", "student");
    const mine = (calendar.json().data as { assignmentId: string | null }[]).filter(
      (event) => event.assignmentId === created.id,
    );
    assert.equal(mine.length, 1);
  });

  test("title and dueAt changes update the same event", async () => {
    const created = await create({ title: "Draft one", dueAt: DUE });
    const [original] = await linkedEvents(created.id);
    const newDue = "2027-01-10T09:30:00";
    await call("PATCH", `/assignments/${created.id}`, "teacher", { title: "Final one", dueAt: newDue });
    const events = await linkedEvents(created.id);
    assert.equal(events.length, 1);
    assert.equal(events[0]!.id, original!.id);
    assert.equal(events[0]!.title, "Final one due");
    assert.equal(events[0]!.startsAt, newDue);

    // Closing keeps the deadline on the calendar.
    await call("PATCH", `/assignments/${created.id}`, "teacher", { status: "closed" });
    assert.equal((await linkedEvents(created.id)).length, 1);
  });

  test("drafts have no event; drafting removes it, publishing restores one", async () => {
    const draft = await create({ title: "Quiet", dueAt: DUE, status: "draft" });
    assert.equal((await linkedEvents(draft.id)).length, 0);

    await call("PATCH", `/assignments/${draft.id}`, "teacher", { status: "open" });
    assert.equal((await linkedEvents(draft.id)).length, 1);

    await call("PATCH", `/assignments/${draft.id}`, "teacher", { status: "draft" });
    assert.equal((await linkedEvents(draft.id)).length, 0);

    await call("PATCH", `/assignments/${draft.id}`, "teacher", { title: "Still quiet" });
    assert.equal((await linkedEvents(draft.id)).length, 0);

    await call("PATCH", `/assignments/${draft.id}`, "teacher", { status: "closed" });
    const events = await linkedEvents(draft.id);
    assert.equal(events.length, 1);
    assert.equal(events[0]!.title, "Still quiet due");
  });

  test("seeded events stay unlinked", async () => {
    const all = await getCalendarEvents(new Set(["c-001"]));
    for (const id of ["e-001", "e-002", "e-003", "e-004", "e-005"]) {
      const event = all.find((entry) => entry.id === id);
      assert.ok(event, id);
      assert.equal(event.assignmentId, null);
    }
    const calendar = await call("GET", "/calendar", "teacher");
    const seeded = (calendar.json().data as { id: string; assignmentId: unknown }[]).find(
      (event) => event.id === "e-001",
    );
    assert.equal(seeded?.assignmentId, null);
  });

  test("a linked event cannot be edited or deleted through /calendar", async () => {
    const created = await create({ title: "Linked", dueAt: DUE });
    const [event] = await linkedEvents(created.id);
    for (const who of ["teacher", "admin"] as const) {
      const put = await call("PUT", `/calendar/${event!.id}`, who, { title: "Moved" });
      assert.equal(put.statusCode, 409, put.body);
      assert.deepEqual(put.json(), {
        error: {
          code: "ASSIGNMENT_EVENT",
          message: "This deadline comes from an assignment; edit the assignment instead",
        },
      });
      const del = await call("DELETE", `/calendar/${event!.id}`, who);
      assert.equal(del.statusCode, 409, del.body);
      assert.equal(del.json().error.code, "ASSIGNMENT_EVENT");
    }
    // Non-managers are still refused first.
    assert.equal((await call("PUT", `/calendar/${event!.id}`, "otherTeacher", { title: "x" })).statusCode, 403);
    assert.equal((await call("DELETE", `/calendar/${event!.id}`, "student")).statusCode, 403);
    const [still] = await linkedEvents(created.id);
    assert.equal(still!.title, "Linked due");

    // Unlinked events remain editable.
    const plain = await call("PUT", "/calendar/e-003", "teacher", { title: "Quiz moved" });
    assert.equal(plain.statusCode, 200, plain.body);
    assert.equal(plain.json().data.assignmentId, null);
  });

  test("a new /calendar event reports assignmentId null", async () => {
    const res = await call("POST", "/calendar", "teacher", {
      title: "Office hours",
      kind: "class",
      startsAt: DUE,
      courseId: "c-001",
    });
    assert.equal(res.statusCode, 201, res.body);
    assert.equal(res.json().data.assignmentId, null);
  });
});

import crypto from "node:crypto";
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/create-app";

// Seeded accounts (apps/api/src/store/memory.ts); password123 for all.
const TEACHER = "+15550001001"; // u-teacher-1, teaches c-001
const STUDENT_1 = "+15550001002"; // u-student-1
const STUDENT_2 = "+15550001003"; // u-student-2
const ADMIN = "+15550001005";

let app: FastifyInstance;
const headers: Record<string, { authorization: string }> = {};

async function login(phone: string, password = "password123") {
  const res = await app.inject({
    method: "POST",
    url: "/api/v1/auth/login",
    payload: { phone, password },
  });
  assert.equal(res.statusCode, 200, res.body);
  return { authorization: `Bearer ${res.json().data.token}` };
}

/** A batch signed exactly the way the extension signs it. */
function signedBatch(studentId: string, assignmentId = "a-001") {
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
  return {
    ...batch,
    clientSignature: crypto
      .createHmac("sha256", key)
      .update(JSON.stringify(batch))
      .digest("base64url"),
    clientPublicKey: JSON.stringify({ kty: "oct", k: key.toString("base64url") }),
  };
}

before(async () => {
  app = await buildApp();
  headers.teacher = await login(TEACHER);
  headers.student1 = await login(STUDENT_1);
  headers.student2 = await login(STUDENT_2);
  headers.admin = await login(ADMIN);

  const register = await app.inject({
    method: "POST",
    url: "/api/v1/auth/register",
    payload: { phone: "+15558880001", password: "secret123", role: "teacher" },
  });
  assert.equal(register.statusCode, 201, register.body);
  headers.otherTeacher = { authorization: `Bearer ${register.json().data.token}` };
});

after(async () => {
  await app.close();
});

describe("telemetry upload ownership", () => {
  test("a student cannot upload telemetry for another student", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/telemetry/batches",
      headers: headers.student1,
      payload: signedBatch("u-student-2"),
    });
    assert.equal(res.statusCode, 403);
    assert.equal(res.json().error.code, "FORBIDDEN");

    const report = await app.inject({
      method: "GET",
      url: "/api/v1/integrity/a-001/u-student-2",
      headers: headers.admin,
    });
    assert.equal(report.statusCode, 404, "the forged batch must not create a report");
  });

  test("staff cannot upload telemetry as a student", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/telemetry/batches",
      headers: headers.teacher,
      payload: signedBatch("u-student-1"),
    });
    assert.equal(res.statusCode, 403);
  });

  test("a student can upload their own telemetry", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/telemetry/batches",
      headers: headers.student1,
      payload: signedBatch("u-student-1"),
    });
    assert.equal(res.statusCode, 202, res.body);
  });
});

describe("integrity report access", () => {
  const reportUrl = "/api/v1/integrity/a-001/u-student-1";

  test("the student can read their own report", async () => {
    const res = await app.inject({ method: "GET", url: reportUrl, headers: headers.student1 });
    assert.equal(res.statusCode, 200, res.body);
  });

  test("another student cannot read it", async () => {
    const res = await app.inject({ method: "GET", url: reportUrl, headers: headers.student2 });
    assert.equal(res.statusCode, 403);
    assert.equal(res.json().error.code, "FORBIDDEN");
  });

  test("the course teacher and admins can read it", async () => {
    for (const who of ["teacher", "admin"]) {
      const res = await app.inject({ method: "GET", url: reportUrl, headers: headers[who] });
      assert.equal(res.statusCode, 200, `${who}: ${res.body}`);
    }
  });

  test("a teacher of a different course cannot read it", async () => {
    const res = await app.inject({
      method: "GET",
      url: reportUrl,
      headers: headers.otherTeacher,
    });
    assert.equal(res.statusCode, 403);
  });
});

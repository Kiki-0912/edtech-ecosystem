import crypto from "node:crypto";
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/create-app";
// The extension's own batch builder and signer: these tests post exactly what
// apps/extension/src/background.js uploads.
import {
  aiTabSwitchEvent,
  buildBatch,
  classifyUploadResponse,
  generateSigningJwk,
  needsNewSigningKey,
  signBatch,
} from "../../extension/src/lib.js";

// Seeded accounts (apps/api/src/store/memory.ts); password123 for all.
const STUDENT_1 = "+15550001002"; // u-student-1
const STUDENT_2 = "+15550001003"; // u-student-2

let app: FastifyInstance;
let jwk: JsonWebKey;
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

const keystrokes = (count: number, deltaMs = 200) =>
  Array.from({ length: count }, () => ({
    type: "keystroke",
    payload: { deltaMs },
    occurredAt: new Date().toISOString(),
  }));

async function upload(
  who: string,
  studentId: string,
  assignmentId: string,
  sessionId: string,
  events: unknown[],
) {
  const batch = await signBatch(buildBatch({ studentId, assignmentId, sessionId, events }), jwk);
  const res = await app.inject({
    method: "POST",
    url: "/api/v1/telemetry/batches",
    headers: headers[who],
    payload: batch,
  });
  return { res, batch };
}

async function report(who: string, assignmentId: string, studentId: string) {
  const res = await app.inject({
    method: "GET",
    url: `/api/v1/integrity/${assignmentId}/${studentId}`,
    headers: headers[who],
  });
  assert.equal(res.statusCode, 200, res.body);
  return res.json().data;
}

before(async () => {
  app = await buildApp();
  headers.student1 = await login(STUDENT_1);
  headers.student2 = await login(STUDENT_2);
  jwk = await generateSigningJwk();
});

after(async () => {
  await app.close();
});

describe("extension upload end to end", () => {
  test("a batch built and signed like background.js is accepted (202)", async () => {
    assert.equal(typeof jwk.k, "string", "the exported HMAC JWK carries its key");
    const { res, batch } = await upload("student1", "u-student-1", "a-001", "s-e2e", [
      ...keystrokes(3),
      aiTabSwitchEvent("claude.ai"),
    ]);
    assert.equal(res.statusCode, 202, res.body);
    assert.equal(classifyUploadResponse(res.statusCode, null), "ok");
    assert.equal(JSON.parse(batch.clientPublicKey).k, jwk.k);
    assert.equal(res.json().data.acceptedEvents, 4);
  });

  test("an uploaded ai_tab_switch reaches server scoring and flags", async () => {
    const data = await report("student1", "a-001", "u-student-1");
    assert.equal(data.effortScore.aiTabSwitches, 1);
    assert.equal(data.effortScore.sessionId, "s-e2e");
    assert.ok(data.flags.includes("ai_tab_switch"), JSON.stringify(data.flags));
  });

  test("the old key format (no k) is rejected as INVALID_SIGNATURE 400, not 401", async () => {
    const legacy = { kty: "oct", alg: "HS256" } as JsonWebKey;
    assert.equal(needsNewSigningKey({ privateKey: jwk, publicKey: legacy }), true);
    // Old background.js signed with the full key but sent only { kty, alg }.
    const signed = await signBatch(
      buildBatch({
        studentId: "u-student-1",
        assignmentId: "a-001",
        sessionId: "s-legacy",
        events: keystrokes(1),
      }),
      jwk,
    );
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/telemetry/batches",
      headers: headers.student1,
      payload: { ...signed, clientPublicKey: JSON.stringify(legacy) },
    });
    assert.equal(res.statusCode, 400, res.body);
    assert.equal(res.json().error.code, "INVALID_SIGNATURE");
    assert.equal(classifyUploadResponse(res.statusCode, res.json().error.code), "resign");
  });

  test("a tampered batch is INVALID_SIGNATURE too", async () => {
    const batch = await signBatch(
      buildBatch({
        studentId: "u-student-1",
        assignmentId: "a-001",
        sessionId: "s-tamper",
        events: keystrokes(1),
      }),
      jwk,
    );
    batch.events[0].payload = { deltaMs: 4000 };
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/telemetry/batches",
      headers: headers.student1,
      payload: batch,
    });
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error.code, "INVALID_SIGNATURE");
  });

  test("only a rejected bearer token is a 401 (sign in again)", async () => {
    const batch = await signBatch(
      buildBatch({
        studentId: "u-student-1",
        assignmentId: "a-001",
        sessionId: "s-auth",
        events: keystrokes(1),
      }),
      jwk,
    );
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/telemetry/batches",
      headers: { authorization: "Bearer not-a-token" },
      payload: batch,
    });
    assert.equal(res.statusCode, 401);
    assert.equal(classifyUploadResponse(res.statusCode, res.json().error?.code), "reauth");
  });
});

describe("server scoring accumulates across batches", () => {
  test("a session's score covers every stored batch, not just the latest", async () => {
    const first = await upload("student1", "u-student-1", "a-002", "s-acc", [
      { type: "paste", payload: { characterCount: 900 }, occurredAt: new Date().toISOString() },
    ]);
    assert.equal(first.res.statusCode, 202, first.res.body);

    const second = await upload("student1", "u-student-1", "a-002", "s-acc", keystrokes(50));
    assert.equal(second.res.statusCode, 202, second.res.body);
    const score = second.res.json().data.effortScore;
    assert.equal(score.keystrokes, 50);
    assert.equal(score.pastes, 1, "the paste from the first batch still counts");
    assert.equal(score.pasteVolume, 900);

    const data = await report("student1", "a-002", "u-student-1");
    assert.equal(data.effortScore.keystrokes, 50);
    assert.equal(data.effortScore.pasteVolume, 900);
    assert.ok(data.flags.includes("large_paste"), "flags use the accumulated metrics");
  });

  test("replaying an accepted batchId is idempotent", async () => {
    const { res, batch } = await upload("student1", "u-student-1", "a-003", "s-replay", [
      ...keystrokes(10),
    ]);
    assert.equal(res.statusCode, 202, res.body);

    for (let attempt = 0; attempt < 2; attempt += 1) {
      const again = await app.inject({
        method: "POST",
        url: "/api/v1/telemetry/batches",
        headers: headers.student1,
        payload: batch,
      });
      assert.equal(again.statusCode, 202, again.body);
      assert.equal(again.json().data.acceptedEvents, 0);
      assert.equal(again.json().data.effortScore.keystrokes, 10);
    }

    const data = await report("student1", "a-003", "u-student-1");
    assert.equal(data.effortScore.keystrokes, 10, "a replay must not double count");
  });

  test("another student cannot reuse an accepted batchId", async () => {
    const { batch } = await upload("student1", "u-student-1", "a-003", "s-replay", keystrokes(1));
    const forged = await signBatch(
      {
        ...buildBatch({
          studentId: "u-student-2",
          assignmentId: "a-003",
          sessionId: "s-x",
          events: keystrokes(1),
        }),
        batchId: batch.batchId,
      },
      jwk,
    );
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/telemetry/batches",
      headers: headers.student2,
      payload: forged,
    });
    assert.equal(res.statusCode, 409, res.body);
    assert.equal(res.json().error.code, "BATCH_CONFLICT");
  });
});

describe("effort rows are namespaced by student", () => {
  test("reusing another student's sessionId cannot overwrite their score", async () => {
    const sessionId = `s-shared-${crypto.randomUUID()}`;
    const mine = await upload("student1", "u-student-1", "a-004", sessionId, keystrokes(120));
    assert.equal(mine.res.statusCode, 202, mine.res.body);

    const theirs = await upload("student2", "u-student-2", "a-004", sessionId, [
      { type: "paste", payload: { characterCount: 5000 }, occurredAt: new Date().toISOString() },
    ]);
    assert.equal(theirs.res.statusCode, 202, theirs.res.body);

    const one = await report("student1", "a-004", "u-student-1");
    assert.equal(one.effortScore.keystrokes, 120);
    assert.equal(one.effortScore.pasteVolume, 0);
    assert.equal(one.effortScore.studentId, "u-student-1");
    assert.equal(one.effortScore.sessionId, sessionId, "the client-facing id is unprefixed");

    const two = await report("student2", "a-004", "u-student-2");
    assert.equal(two.effortScore.pasteVolume, 5000);
    assert.equal(two.effortScore.keystrokes, 0);
  });
});

describe("ingestion reads only the uploading pair's batches", () => {
  // POST /telemetry/batches used to read every stored batch (all students)
  // twice per upload; it now uses these scoped lookups.
  test("getTelemetryBatchesFor and getTelemetryBatch are scoped", async () => {
    const { getTelemetryBatch, getTelemetryBatchesFor } = await import("../src/store/db");
    const mine = await upload("student1", "u-student-1", "a-001", "s-scope", keystrokes(3));
    const theirs = await upload("student2", "u-student-2", "a-001", "s-scope", keystrokes(4));
    assert.equal(mine.res.statusCode, 202, mine.res.body);
    assert.equal(theirs.res.statusCode, 202, theirs.res.body);

    const pair = await getTelemetryBatchesFor("u-student-1", "a-001");
    assert.ok(pair.length >= 1);
    assert.ok(pair.every((b) => b.studentId === "u-student-1" && b.assignmentId === "a-001"));
    assert.ok(pair.some((b) => b.batchId === mine.batch.batchId));
    assert.equal((await getTelemetryBatch(theirs.batch.batchId))?.studentId, "u-student-2");
    assert.equal(await getTelemetryBatch("no-such-batch"), undefined);
    // Scoring still covers only the pair: student 2's keystrokes are not counted.
    assert.equal(mine.res.json().data.effortScore.keystrokes, 3);
    assert.equal(theirs.res.json().data.effortScore.keystrokes, 4);
  });
});

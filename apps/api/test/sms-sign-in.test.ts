// SMS sign-in limits: only the newest code works, wrong guesses and sends are
// capped per phone, and admin accounts cannot sign in by SMS at all.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance, LightMyRequestResponse } from "fastify";
import { buildApp } from "../src/create-app";

const ADMIN = "+15550001005"; // u-admin-1
const TEACHER = "+15550001001"; // u-teacher-1
const STUDENTS = ["+15550001002", "+15550001003", "+15550001004", "+15550001006"];

let app: FastifyInstance;

const sendSms = (phone: string) =>
  app.inject({ method: "POST", url: "/api/v1/auth/send-sms", payload: { phone } });

const verifySms = (phone: string, code: string) =>
  app.inject({ method: "POST", url: "/api/v1/auth/verify-sms", payload: { phone, code } });

/** Send a code and return it (SMS_DEV_ECHO is on in this file). */
async function codeFor(phone: string): Promise<string> {
  const res = await sendSms(phone);
  assert.equal(res.statusCode, 200, res.body);
  return res.json().data.code;
}

/** A six-digit code other than `code`. */
const wrong = (code: string, offset = 1) =>
  String(100000 + ((Number(code) - 100000 + offset) % 900000));

function expectError(res: LightMyRequestResponse, status: number, code: string) {
  assert.equal(res.statusCode, status, res.body);
  assert.equal(res.json().error.code, code, res.body);
}

before(async () => {
  process.env.SMS_DEV_ECHO = "true";
  app = await buildApp();
});

after(async () => {
  delete process.env.SMS_DEV_ECHO;
  await app.close();
});

describe("SMS sign-in", () => {
  test("admins cannot request or use SMS codes", async () => {
    expectError(await sendSms(ADMIN), 403, "SMS_SIGN_IN_DISABLED");
    expectError(await verifySms(ADMIN, "123456"), 403, "SMS_SIGN_IN_DISABLED");
  });

  test("a new code replaces the earlier ones", async () => {
    const phone = STUDENTS[0];
    const first = await codeFor(phone);
    const second = await codeFor(phone);
    if (first !== second) {
      expectError(await verifySms(phone, first), 400, "INVALID_CODE");
    }
    const res = await verifySms(phone, second);
    assert.equal(res.statusCode, 200, res.body);
    assert.ok(res.json().data.token);
    // Codes are single use.
    expectError(await verifySms(phone, second), 400, "INVALID_CODE");
  });

  test("a code stops working after five wrong guesses", async () => {
    const phone = STUDENTS[1];
    const code = await codeFor(phone);
    for (let attempt = 1; attempt <= 5; attempt++) {
      expectError(await verifySms(phone, wrong(code, attempt)), 400, "INVALID_CODE");
    }
    expectError(await verifySms(phone, code), 400, "INVALID_CODE");

    // A new code works again.
    const next = await codeFor(phone);
    assert.equal((await verifySms(phone, next)).statusCode, 200);
  });

  test("a phone gets at most five codes an hour", async () => {
    const phone = STUDENTS[2];
    for (let sent = 1; sent <= 5; sent++) {
      assert.equal((await sendSms(phone)).statusCode, 200, `send ${sent}`);
    }
    expectError(await sendSms(phone), 429, "RATE_LIMITED");
    // Other phones are not affected.
    assert.equal((await sendSms(STUDENTS[3])).statusCode, 200);
  });

  test("a flood of sends cannot widen the odds of guessing", async () => {
    // The scenario from the security review: many outstanding codes, then
    // guesses. At most five codes exist per hour, and only the newest counts.
    const phone = TEACHER;
    const responses = await Promise.all(Array.from({ length: 20 }, () => sendSms(phone)));
    const codes: string[] = responses
      .filter((res) => res.statusCode === 200)
      .map((res) => res.json().data.code);
    assert.equal(codes.length, 5);
    assert.equal(responses.filter((res) => res.statusCode === 429).length, 15);
    // Whichever code was stored last is the only one that verifies (the four
    // older ones count as wrong guesses, still under the limit of five).
    const statuses: number[] = [];
    for (const code of codes) statuses.push((await verifySms(phone, code)).statusCode);
    assert.equal(statuses.filter((status) => status === 200).length, 1, statuses.join(","));
  });
});

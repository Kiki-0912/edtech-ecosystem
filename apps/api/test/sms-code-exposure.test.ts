import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/create-app";

const ADMIN_PHONE = "+15550001005";
let app: FastifyInstance;

const sendSms = () =>
  app.inject({ method: "POST", url: "/api/v1/auth/send-sms", payload: { phone: ADMIN_PHONE } });

before(async () => {
  delete process.env.SMS_DEV_ECHO;
  app = await buildApp();
});

after(async () => {
  delete process.env.SMS_DEV_ECHO;
  await app.close();
});

test("the SMS code is never returned by default, whatever NODE_ENV is", async () => {
  for (const nodeEnv of [undefined, "development", "production"]) {
    if (nodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = nodeEnv;
    const res = await sendSms();
    assert.equal(res.statusCode, 200, res.body);
    assert.equal(res.json().data.code, undefined, `NODE_ENV=${nodeEnv}`);
  }
});

test("local demos can opt in with SMS_DEV_ECHO=true", async () => {
  process.env.SMS_DEV_ECHO = "true";
  const res = await sendSms();
  const code = res.json().data.code;
  assert.match(code, /^\d{6}$/);

  const verify = await app.inject({
    method: "POST",
    url: "/api/v1/auth/verify-sms",
    payload: { phone: ADMIN_PHONE, code },
  });
  assert.equal(verify.statusCode, 200, verify.body);
});

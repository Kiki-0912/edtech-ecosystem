import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance } from "fastify";

// config.ts reads env at import time, so set it before importing the app.
process.env.SEED_DEMO_PASSWORD = "seed-test-pass-42";
process.env.SEED_ADMIN_EMAIL = "seeded-admin@example.test";

let app: FastifyInstance;

const login = (payload: Record<string, string>) =>
  app.inject({ method: "POST", url: "/api/v1/auth/login", payload });

before(async () => {
  const { buildApp } = await import("../src/create-app");
  app = await buildApp();
});

after(async () => {
  await app.close();
});

test("the seeded admin signs in with the configured email and password", async () => {
  const res = await login({ email: "seeded-admin@example.test", password: "seed-test-pass-42" });
  assert.equal(res.statusCode, 200, res.body);
  assert.equal(res.json().data.user.role, "admin");
});

test("the public demo password no longer works for any seeded account", async () => {
  for (const phone of ["+15550001001", "+15550001002", "+15550001005"]) {
    const res = await login({ phone, password: "password123" });
    assert.equal(res.statusCode, 401, phone);
  }
  const teacher = await login({ phone: "+15550001001", password: "seed-test-pass-42" });
  assert.equal(teacher.statusCode, 200, teacher.body);
});

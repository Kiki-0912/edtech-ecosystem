// The Netlify Function adapter: web Request in → Fastify → web Response out.
import { test } from "node:test";
import assert from "node:assert/strict";
import handler, { config } from "../netlify/functions/api.mts";

const BASE = "https://edtech-api.example.netlify.app";

test("routes every path to the function", () => {
  assert.deepEqual(config.path, ["/", "/*"]);
});

test("serves public routes", async () => {
  const res = await handler(new Request(`${BASE}/health`));
  assert.equal(res.status, 200);
  assert.match(res.headers.get("content-type") ?? "", /application\/json/);
  assert.equal((await res.json()).status, "ok");
});

test("passes JSON bodies, query strings and auth headers through", async () => {
  const login = await handler(
    new Request(`${BASE}/api/v1/auth/login`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "+15550001005", password: "password123" }),
    }),
  );
  assert.equal(login.status, 200);
  const { token } = (await login.json()).data;

  const notes = await handler(
    new Request(`${BASE}/api/v1/notes?courseId=c-001`, {
      headers: { authorization: `Bearer ${token}` },
    }),
  );
  assert.equal(notes.status, 200);
  assert.ok((await notes.json()).data.length > 0);
});

test("keeps the error envelope and status codes", async () => {
  const res = await handler(new Request(`${BASE}/api/v1/courses`));
  assert.equal(res.status, 401);
  assert.equal((await res.json()).error.code, "UNAUTHORIZED");
});

test("answers CORS preflight", async () => {
  const res = await handler(
    new Request(`${BASE}/api/v1/courses`, {
      method: "OPTIONS",
      headers: {
        origin: "https://app.example.com",
        "access-control-request-method": "GET",
        "access-control-request-headers": "authorization",
      },
    }),
  );
  assert.equal(res.status, 204);
  assert.ok(res.headers.get("access-control-allow-origin"));
});

// The Netlify Function adapter: web Request in → Fastify → web Response out.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { test } from "node:test";
import assert from "node:assert/strict";
import handler from "../src/netlify-handler";
import { buildNetlifyHandler, DEFAULT_OUTFILE } from "../src/scripts/build-netlify-handler";

const BASE = "https://edtech-api.example.netlify.app";

test("the deployed bundle runs where require(esm) is unavailable (Netlify's Lambda)", async () => {
  // Build exactly what Netlify deploys, then check the function file's wiring.
  await buildNetlifyHandler(DEFAULT_OUTFILE);
  const fn = await import("../netlify/functions/api.mts");
  assert.deepEqual(fn.config.path, ["/", "/*"]);
  assert.equal(typeof fn.default, "function");

  // Production crashed with ERR_REQUIRE_ESM (light-my-request -> cookie@2).
  const script = `
    const { default: handler } = await import(${JSON.stringify(DEFAULT_OUTFILE)});
    const res = await handler(new Request("https://x.test/health"));
    console.log("RESULT " + JSON.stringify({ status: res.status, body: await res.json() }));
    process.exit(0);`;
  const env = { ...process.env };
  for (const key of ["DATABASE_URL", "NETLIFY_DB_URL", "NETLIFY_DATABASE_URL"]) delete env[key];
  const { stdout } = await promisify(execFile)(
    process.execPath,
    ["--no-experimental-require-module", "--input-type=module", "-e", script],
    { env },
  );
  // stdout also carries the API's JSON log lines; pick out the marked result.
  const line = stdout.split("\n").find((entry) => entry.startsWith("RESULT "));
  assert.ok(line, stdout);
  const result = JSON.parse(line.slice("RESULT ".length));
  assert.equal(result.status, 200);
  assert.equal(result.body.status, "ok");
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

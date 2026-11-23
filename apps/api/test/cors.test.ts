// CORS_ORIGIN accepts a comma-separated list, so the web app and the separately
// deployed admin console can both call a locked-down API.
import { afterEach, describe, test } from "node:test";
import assert from "node:assert/strict";
import { parseCorsOrigin } from "../src/config";
import { buildApp } from "../src/create-app";

const WEB = "https://app.example.org";
const ADMIN = "https://admin.example.org";

/** The preflight response for `origin` with CORS_ORIGIN set to `allowed`. */
async function preflight(allowed: string | undefined, origin: string) {
  if (allowed === undefined) delete process.env.CORS_ORIGIN;
  else process.env.CORS_ORIGIN = allowed;
  const app = await buildApp();
  try {
    return await app.inject({
      method: "OPTIONS",
      url: "/api/v1/admin/users",
      headers: {
        origin,
        "access-control-request-method": "GET",
        "access-control-request-headers": "authorization",
      },
    });
  } finally {
    await app.close();
  }
}

afterEach(() => {
  delete process.env.CORS_ORIGIN;
});

describe("CORS_ORIGIN", () => {
  test("parses unset, '*', one origin and a comma-separated list", () => {
    assert.equal(parseCorsOrigin(undefined), "*");
    assert.equal(parseCorsOrigin("*"), "*");
    assert.deepEqual(parseCorsOrigin(WEB), [WEB]);
    assert.deepEqual(parseCorsOrigin(` ${WEB}/ , ${ADMIN} ,`), [WEB, ADMIN]);
    assert.equal(parseCorsOrigin(`${WEB},*`), "*");
    // Set but empty allows no cross-origin caller (it used to send an empty header).
    assert.deepEqual(parseCorsOrigin(""), []);
  });

  test("each listed origin gets its own origin back; others get none", async () => {
    const list = `${WEB},${ADMIN}`;
    for (const origin of [WEB, ADMIN]) {
      const res = await preflight(list, origin);
      assert.equal(res.statusCode, 204, res.body);
      assert.equal(res.headers["access-control-allow-origin"], origin);
    }
    const other = await preflight(list, "https://evil.example");
    assert.equal(other.headers["access-control-allow-origin"], undefined);
  });

  test("the default still allows any origin", async () => {
    const res = await preflight(undefined, ADMIN);
    assert.equal(res.headers["access-control-allow-origin"], "*");
  });
});

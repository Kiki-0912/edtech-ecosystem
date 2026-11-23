// Production refuses to start without a real AUTH_SECRET; local dev and tests
// keep working with the fallback.
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { DEV_AUTH_SECRET, assertSafeConfig, unsafeConfigReason } from "../src/config";

describe("unsafeConfigReason", () => {
  test("development without AUTH_SECRET is fine", () => {
    assert.equal(
      unsafeConfigReason({ nodeEnv: "development", authSecret: undefined, onNetlify: false }),
      null,
    );
    assert.equal(
      unsafeConfigReason({ nodeEnv: undefined, authSecret: undefined, onNetlify: false }),
      null,
    );
  });

  test("production without AUTH_SECRET, blank or the dev fallback is refused", () => {
    for (const authSecret of [undefined, "", "  ", DEV_AUTH_SECRET]) {
      assert.ok(unsafeConfigReason({ nodeEnv: "production", authSecret, onNetlify: false }));
    }
  });

  test("Netlify counts as production whatever NODE_ENV says", () => {
    assert.ok(unsafeConfigReason({ nodeEnv: "development", authSecret: undefined, onNetlify: true }));
    assert.equal(
      unsafeConfigReason({ nodeEnv: undefined, authSecret: "a-real-secret", onNetlify: true }),
      null,
    );
  });

  test("production with a real secret is fine", () => {
    assert.equal(
      unsafeConfigReason({ nodeEnv: "production", authSecret: "a-real-secret", onNetlify: false }),
      null,
    );
  });
});

describe("assertSafeConfig", () => {
  test("throws for NODE_ENV=production without AUTH_SECRET", () => {
    const saved = { nodeEnv: process.env.NODE_ENV, secret: process.env.AUTH_SECRET };
    try {
      process.env.NODE_ENV = "production";
      delete process.env.AUTH_SECRET;
      assert.throws(() => assertSafeConfig(), /Refusing to start/);
      process.env.AUTH_SECRET = "a-real-secret";
      assert.doesNotThrow(() => assertSafeConfig());
    } finally {
      if (saved.nodeEnv === undefined) delete process.env.NODE_ENV;
      else process.env.NODE_ENV = saved.nodeEnv;
      if (saved.secret === undefined) delete process.env.AUTH_SECRET;
      else process.env.AUTH_SECRET = saved.secret;
    }
  });
});

describe("docker-compose.yml", () => {
  // Compose interpolates the whole file before picking services, so a required
  // (`:?`) AUTH_SECRET on the api service would break `npm run db:up`.
  test("AUTH_SECRET is optional to compose but blank is refused by the API", async () => {
    const { readFile } = await import("node:fs/promises");
    const compose = await readFile(new URL("../../../docker-compose.yml", import.meta.url), "utf8");
    assert.doesNotMatch(compose, /\$\{AUTH_SECRET:\?/);
    assert.match(compose, /AUTH_SECRET=\$\{AUTH_SECRET:-\}/);
    assert.match(compose, /NODE_ENV=production/);
    assert.ok(unsafeConfigReason({ nodeEnv: "production", authSecret: "", onNetlify: false }));
  });
});

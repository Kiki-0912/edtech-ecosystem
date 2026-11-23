// Unit tests for the Integrity Lens extension's pure logic. The extension has
// no harness of its own, so its helpers (lib.js, privacy.js) and manifest are
// loaded here in Node. No chrome.* APIs are touched.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import {
  addToBucket,
  aiTabSwitchEvent,
  canonicalBatch,
  classifyUploadResponse,
  createLock,
  effectiveOrigins,
  isMonitoredUrl,
  latestActiveSession,
  needsNewSigningKey,
  nextUploadable,
  originMatchPattern,
  parseOrigins,
  queueStats,
  retryDelayMs,
  sanitizeContentEvents,
  RETRY_MAX_MS,
} from "../../extension/src/lib.js";

const EXT = new URL("../../extension/", import.meta.url);
const read = (path: string) => readFileSync(new URL(path, EXT), "utf8");

/* ---------- privacy.js (content-script filter) ---------- */

interface FakeElement {
  nodeType: 1;
  tagName: string;
  attrs: Record<string, string>;
  getAttribute(name: string): string | null;
  hasAttribute(name: string): boolean;
}

function el(tagName: string, attrs: Record<string, string> = {}): FakeElement {
  return {
    nodeType: 1,
    tagName,
    attrs,
    getAttribute: (name) => attrs[name] ?? null,
    hasAttribute: (name) => name in attrs,
  };
}

function loadPrivacy() {
  const sandbox: { IntegrityLensPrivacy?: { isSensitiveEvent(event: unknown): boolean } } = {};
  vm.runInNewContext(read("src/privacy.js"), { globalThis: sandbox });
  assert.ok(sandbox.IntegrityLensPrivacy, "privacy.js defines IntegrityLensPrivacy");
  return sandbox.IntegrityLensPrivacy;
}

/** An event whose composedPath() is the given chain, innermost first. */
const eventOn = (...path: unknown[]) => ({ target: path.at(-1), composedPath: () => path });

describe("extension privacy filter", () => {
  const privacy = loadPrivacy();
  const doc = { nodeType: 9 };

  test("password and hidden inputs are sensitive; text inputs are not", () => {
    assert.equal(privacy.isSensitiveEvent(eventOn(el("INPUT", { type: "password" }), doc)), true);
    assert.equal(privacy.isSensitiveEvent(eventOn(el("INPUT", { type: "HIDDEN" }), doc)), true);
    assert.equal(privacy.isSensitiveEvent(eventOn(el("INPUT", { type: "text" }), doc)), false);
    assert.equal(privacy.isSensitiveEvent(eventOn(el("TEXTAREA"), doc)), false);
  });

  test("[data-sensitive] applies to inputs too (checked before the input branch)", () => {
    const wrapper = el("DIV", { "data-sensitive": "" });
    assert.equal(privacy.isSensitiveEvent(eventOn(el("INPUT", { type: "text" }), wrapper)), true);
    assert.equal(privacy.isSensitiveEvent(eventOn(el("INPUT", { "data-sensitive": "" }))), true);
  });

  test("shadow DOM: the real target comes from composedPath()[0]", () => {
    // Retargeted: event.target is the shadow host, the real target is inside.
    const host = el("MY-FIELD");
    const inner = el("INPUT", { type: "password" });
    const shadowRoot = { nodeType: 11 };
    const event = { target: host, composedPath: () => [inner, shadowRoot, host, doc] };
    assert.equal(privacy.isSensitiveEvent(event), true);

    // A [data-sensitive] host covers everything inside its shadow root.
    const sensitiveHost = el("MY-EDITOR", { "data-sensitive": "" });
    const text = el("DIV");
    assert.equal(privacy.isSensitiveEvent(eventOn(text, shadowRoot, sensitiveHost, doc)), true);
  });

  test("mouse targets over [data-sensitive] regions are sensitive", () => {
    const region = el("SECTION", { "data-sensitive": "" });
    assert.equal(privacy.isSensitiveEvent(eventOn(el("SPAN"), region, doc)), true);
    assert.equal(privacy.isSensitiveEvent(eventOn(el("SPAN"), el("SECTION"), doc)), false);
  });

  test("content.js consults the filter for keys, pastes and mouse movement", () => {
    const content = read("src/content.js");
    assert.equal(content.match(/isSensitiveEvent\(event\)/g)?.length, 3);
    assert.doesNotMatch(content, /event\.key\b(?!\))/, "key content is never read");
  });
});

/* ---------- signing and upload outcomes ---------- */

describe("extension signing key and upload outcomes", () => {
  const full = { kty: "oct", k: "c2VjcmV0", alg: "HS256" };

  test("a stored key without k is regenerated", () => {
    assert.equal(needsNewSigningKey(undefined), true);
    assert.equal(needsNewSigningKey({ privateKey: full, publicKey: { kty: "oct" } }), true);
    assert.equal(needsNewSigningKey({ privateKey: full, publicKey: full }), false);
  });

  test("401 means sign in again; a bad signature does not", () => {
    assert.equal(classifyUploadResponse(202, null), "ok");
    assert.equal(classifyUploadResponse(401, "UNAUTHORIZED"), "reauth");
    assert.equal(classifyUploadResponse(400, "INVALID_SIGNATURE"), "resign");
    assert.equal(classifyUploadResponse(403, "FORBIDDEN"), "drop");
    assert.equal(classifyUploadResponse(404, "ASSIGNMENT_NOT_FOUND"), "drop");
    assert.equal(classifyUploadResponse(409, "BATCH_CONFLICT"), "drop");
    assert.equal(classifyUploadResponse(0, null), "retry");
    assert.equal(classifyUploadResponse(429, null), "retry");
    assert.equal(classifyUploadResponse(503, null), "retry");
  });

  test("backoff doubles and is capped", () => {
    assert.ok(retryDelayMs(2) === 2 * retryDelayMs(1));
    assert.equal(retryDelayMs(30), RETRY_MAX_MS);
  });

  test("the canonical JSON keeps the key order the API verifies", () => {
    const json = canonicalBatch({
      events: [],
      createdAt: "c",
      assignmentId: "a",
      studentId: "s",
      batchId: "b",
      extra: "ignored",
    });
    assert.equal(json, '{"batchId":"b","studentId":"s","assignmentId":"a","createdAt":"c","events":[]}');
  });
});

/* ---------- events ---------- */

describe("extension event handling", () => {
  test("content events keep only known types and one finite number", () => {
    const clean = sanitizeContentEvents(
      [
        { type: "keystroke", payload: { deltaMs: 120, key: "a" }, occurredAt: "2026-01-01T00:00:00Z" },
        { type: "paste", payload: { characterCount: "12", text: "secret" } },
        { type: "ai_tab_switch", payload: { host: "claude.ai" } },
        { type: "cursor", payload: { distancePx: Number.NaN } },
      ],
      "2026-02-02T00:00:00Z",
    );
    assert.deepEqual(clean, [
      { type: "keystroke", payload: { deltaMs: 120 }, occurredAt: "2026-01-01T00:00:00Z" },
      { type: "paste", payload: { characterCount: 12 }, occurredAt: "2026-02-02T00:00:00Z" },
      { type: "cursor", payload: { distancePx: 0 }, occurredAt: "2026-02-02T00:00:00Z" },
    ]);
  });

  test("an AI tab switch becomes an uploadable ai_tab_switch event", () => {
    const pending: Record<string, { events: unknown[] }> = {};
    const now = Date.now();
    const sessions = {
      7: { sessionId: "s-7", lastActiveAt: now - 1_000 },
      8: { sessionId: "s-8", lastActiveAt: now - 60 * 60 * 1000 },
    };
    const found = latestActiveSession(sessions, now, 30 * 60 * 1000);
    assert.equal(found?.[0], "7");
    addToBucket(pending, "7", {
      sessionId: "s-7",
      ownerId: "u-student-1",
      events: [aiTabSwitchEvent("claude.ai", "2026-01-01T00:00:00Z")],
      maxEvents: 10,
    });
    assert.deepEqual(pending["7"].events, [
      { type: "ai_tab_switch", payload: { host: "claude.ai" }, occurredAt: "2026-01-01T00:00:00Z" },
    ]);
  });
});

/* ---------- account partitioning ---------- */

describe("extension queue is partitioned by account", () => {
  test("events captured under another account start a fresh bucket", () => {
    const pending = {};
    const add = (ownerId: string, n: number) =>
      addToBucket(pending, "1", {
        sessionId: "s",
        ownerId,
        events: Array.from({ length: n }, () => ({ type: "keystroke" })),
        maxEvents: 100,
      });
    add("u-student-1", 3);
    const bucket = add("u-student-2", 2);
    assert.equal(bucket.ownerId, "u-student-2");
    assert.equal(bucket.events.length, 2, "student 1's events are not uploaded as student 2");
  });

  test("only the signed-in student's batches upload or count", () => {
    const queue = [
      { batch: { studentId: "u-student-1", events: [1, 2] }, nextAttemptAt: 0 },
      { batch: { studentId: "u-student-2", events: [1] }, nextAttemptAt: 0 },
    ];
    assert.equal(nextUploadable(queue, "u-student-2", 10)?.batch.studentId, "u-student-2");
    assert.equal(nextUploadable(queue, "u-student-3", 10), null);
    assert.deepEqual(queueStats(queue, "u-student-1"), { pendingBatches: 1, pendingEvents: 2 });
    queue[0].nextAttemptAt = 50;
    assert.equal(nextUploadable(queue, "u-student-1", 10), null, "backoff is respected");
  });
});

/* ---------- monitored origins ---------- */

describe("extension monitored origins", () => {
  test("uploads default to the API origin only", () => {
    const origins = effectiveOrigins({ apiBaseUrl: "http://localhost:4000/" });
    assert.deepEqual(origins, ["http://localhost:4000"]);
    assert.equal(isMonitoredUrl("http://localhost:4000/a?assignmentId=a-001", origins), true);
    assert.equal(isMonitoredUrl("https://evil.example/?assignmentId=a-001", origins), false);
    assert.equal(isMonitoredUrl("http://localhost:4001/", origins), false);
    assert.equal(isMonitoredUrl("not a url", origins), false);
  });

  test("configured origins replace the default and are normalised", () => {
    assert.deepEqual(
      parseOrigins("https://lms.school.edu/course/1\nftp://x.y\nhttps://lms.school.edu, bad"),
      ["https://lms.school.edu"],
    );
    const origins = effectiveOrigins({ allowedOrigins: ["https://lms.school.edu"] });
    assert.equal(isMonitoredUrl("https://lms.school.edu/x", origins), true);
    assert.equal(isMonitoredUrl("https://lms.school.edu.evil.example/x", origins), false);
    assert.equal(originMatchPattern("http://localhost:4000"), "http://localhost:4000/*");
  });
});

/* ---------- storage lock ---------- */

describe("extension storage lock", () => {
  test("concurrent read-modify-writes never lose an update", async () => {
    const withLock = createLock();
    let stored: number[] = [];
    const tick = () => new Promise((resolve) => setTimeout(resolve, Math.random() * 3));
    const append = (value: number) =>
      withLock(async () => {
        const copy = [...stored];
        await tick();
        copy.push(value);
        await tick();
        stored = copy;
      });
    await Promise.all(Array.from({ length: 40 }, (_, i) => append(i)));
    assert.deepEqual(stored, Array.from({ length: 40 }, (_, i) => i));
  });

  test("a failing task does not wedge the lock", async () => {
    const withLock = createLock();
    await assert.rejects(withLock(async () => Promise.reject(new Error("boom"))));
    assert.equal(await withLock(async () => 42), 42);
  });
});

/* ---------- manifest and worker wiring ---------- */

describe("extension manifest and service worker", () => {
  const manifest = JSON.parse(read("manifest.json"));
  const background = read("src/background.js");

  test("host permissions cover the real API origins (and /health)", () => {
    assert.ok(manifest.host_permissions.includes("http://localhost:4000/*"));
    assert.ok(manifest.host_permissions.includes("https://edtech-ecosystem-api.netlify.app/*"));
    assert.ok(manifest.permissions.includes("alarms"));
    assert.ok(manifest.permissions.includes("scripting"));
  });

  test("capture scripts are not injected everywhere; LMS origins are opt-in", () => {
    assert.equal(manifest.content_scripts, undefined);
    assert.deepEqual(manifest.optional_host_permissions, ["http://*/*", "https://*/*"]);
    assert.match(background, /registerContentScripts/);
    assert.match(background, /"src\/privacy\.js", "src\/content\.js"/);
  });

  test("the worker uses chrome.alarms, not timers or onSuspend", () => {
    const code = background.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
    assert.doesNotMatch(code, /setInterval|setTimeout/);
    assert.doesNotMatch(code, /onSuspend/);
    assert.match(background, /chrome\.alarms\.onAlarm/);
  });

  test("the options Flush button runs a real flush", () => {
    assert.match(read("src/options.js"), /type: "flush-now"/);
    assert.match(background, /message\?\.type === "flush-now"/);
  });
});

// Pure helpers for the Integrity Lens service worker. No chrome.* access here,
// so apps/api/test/telemetry-extension.test.ts can load this file in Node.

export const AI_HOSTS = [
  "chatgpt.com",
  "chat.openai.com",
  "claude.ai",
  "gemini.google.com",
  "copilot.microsoft.com",
  "perplexity.ai",
];

export const DEFAULT_API_BASE_URL = "http://localhost:4000";
export const RETRY_BASE_MS = 10_000;
export const RETRY_MAX_MS = 5 * 60 * 1000;
export const MAX_SIGNATURE_FAILURES = 2;

/** Event types a content script may report, with the one numeric field each keeps. */
const CONTENT_EVENT_FIELDS = {
  keystroke: "deltaMs",
  paste: "characterCount",
  cursor: "distancePx",
};

export function normalizeBaseUrl(url) {
  return String(url ?? "").trim().replace(/\/+$/, "");
}

export function hostFromUrl(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return null;
  }
}

export function isAiHost(host) {
  return AI_HOSTS.some((aiHost) => host === aiHost || host.endsWith(`.${aiHost}`));
}

/* ---------- monitored (LMS) origins ---------- */

/** "https://lms.school.edu/path" -> "https://lms.school.edu"; null unless http(s). */
export function normalizeOrigin(url) {
  try {
    const parsed = new URL(String(url ?? "").trim());
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
      return null;
    }
    return parsed.origin;
  } catch {
    return null;
  }
}

/** Match pattern for chrome.permissions / chrome.scripting, port included
 *  ("http://localhost:4000" -> "http://localhost:4000/*"). */
export function originMatchPattern(origin) {
  return `${new URL(origin).origin}/*`;
}

/** Unique, valid origins from user input; invalid lines are dropped. */
export function parseOrigins(values) {
  const list = Array.isArray(values) ? values : String(values ?? "").split(/[\s,]+/);
  const origins = [];
  for (const value of list) {
    const origin = normalizeOrigin(value);
    if (origin && !origins.includes(origin)) {
      origins.push(origin);
    }
  }
  return origins;
}

/** Configured origins, or the API origin when the student never set any. */
export function effectiveOrigins(settings) {
  if (Array.isArray(settings?.allowedOrigins)) {
    return parseOrigins(settings.allowedOrigins);
  }
  return parseOrigins([normalizeBaseUrl(settings?.apiBaseUrl ?? DEFAULT_API_BASE_URL)]);
}

/**
 * Stable key for "the same document", used to remember which assignment a
 * student linked to it: Google Docs/Sheets/Slides/Forms by file id (so /edit,
 * /view and account switches map to one key), anything else by origin + path.
 */
export function documentKey(url) {
  try {
    const parsed = new URL(String(url ?? ""));
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
      return null;
    }
    const google = parsed.pathname.match(
      /^\/(document|spreadsheets|presentation|forms)\/(?:u\/\d+\/)?d\/([^/]+)/,
    );
    if (google) {
      return `${parsed.origin}/${google[1]}/d/${google[2]}`;
    }
    return `${parsed.origin}${parsed.pathname.replace(/\/+$/, "")}`;
  } catch {
    return null;
  }
}

/**
 * Which assignment a tab's telemetry belongs to. A link the student picked in
 * the popup wins, then an assignmentId the page itself provides; leaving a
 * linked document drops its assignment. Unmonitored sites never get one.
 */
export function resolveAssignment({ monitored, link, pageAssignmentId, docKey, session }) {
  if (!monitored) {
    return { assignmentId: null, linkedDocKey: null };
  }
  if (link?.assignmentId) {
    return { assignmentId: link.assignmentId, linkedDocKey: docKey };
  }
  if (typeof pageAssignmentId === "string" && pageAssignmentId && pageAssignmentId !== "unassigned") {
    return { assignmentId: pageAssignmentId, linkedDocKey: null };
  }
  if (session?.linkedDocKey && session.linkedDocKey !== docKey) {
    return { assignmentId: null, linkedDocKey: null };
  }
  return { assignmentId: session?.assignmentId ?? null, linkedDocKey: session?.linkedDocKey ?? null };
}

/** Only pages on an exact configured origin may attach sessions to assignments. */
export function isMonitoredUrl(url, origins) {
  const origin = normalizeOrigin(url);
  return origin !== null && origins.includes(origin);
}

/* ---------- scoring (mirrors apps/api/src/services/effort.ts) ---------- */

export function emptySession(tabId, url, now = Date.now(), uuid = () => crypto.randomUUID()) {
  return {
    tabId,
    url,
    sessionId: uuid(),
    assignmentId: null,
    keystrokes: 0,
    pastes: 0,
    pasteVolume: 0,
    aiTabSwitches: 0,
    activeMs: 0,
    activeSeconds: 0,
    score: 100,
    startedAt: now,
    lastActiveAt: now,
    updatedAt: now,
  };
}

export function computeScore(session) {
  const totalInput = session.keystrokes + session.pasteVolume;
  const pasteRatio = totalInput === 0 ? 0 : session.pasteVolume / totalInput;
  const pastePenalty = Math.round(Math.min(45, pasteRatio * 100));
  const aiPenalty = Math.min(30, session.aiTabSwitches * 10);
  const idlePenalty = session.activeSeconds < 60 && session.pastes > 0 ? 10 : 0;
  return Math.max(0, Math.min(100, 100 - pastePenalty - aiPenalty - idlePenalty));
}

/** Keep only known content-script event types and a single finite number per
 *  event, so a page can never smuggle text (or an ai_tab_switch) into a batch. */
export function sanitizeContentEvents(events, nowIso = new Date().toISOString()) {
  if (!Array.isArray(events)) {
    return [];
  }
  const clean = [];
  for (const event of events) {
    const field = CONTENT_EVENT_FIELDS[event?.type];
    if (!field) {
      continue;
    }
    const value = Number(event.payload?.[field] ?? 0);
    const occurredAt =
      typeof event.occurredAt === "string" && !Number.isNaN(Date.parse(event.occurredAt))
        ? event.occurredAt
        : nowIso;
    clean.push({
      type: event.type,
      payload: { [field]: Number.isFinite(value) ? value : 0 },
      occurredAt,
    });
  }
  return clean;
}

export function applyEvents(session, events, now = Date.now()) {
  for (const event of events) {
    if (event.type === "keystroke") {
      session.keystrokes += 1;
      const delta = Number(event.payload?.deltaMs ?? 0);
      session.activeMs += Number.isFinite(delta) ? Math.min(Math.max(delta, 0), 5000) : 0;
    } else if (event.type === "paste") {
      session.pastes += 1;
      const characters = Number(event.payload?.characterCount ?? 0);
      session.pasteVolume += Number.isFinite(characters) ? Math.max(0, Math.floor(characters)) : 0;
    } else if (event.type === "cursor") {
      const distance = Number(event.payload?.distancePx ?? 0);
      session.cursorDistancePx =
        (session.cursorDistancePx ?? 0) +
        (Number.isFinite(distance) ? Math.max(0, Math.round(distance)) : 0);
    }
  }

  session.activeSeconds = Math.round(session.activeMs / 1000);
  session.score = computeScore(session);
  session.lastActiveAt = now;
  session.updatedAt = now;
  return session;
}

/** Most recently active session within the window, as [tabId, session] or null. */
export function latestActiveSession(sessions, now, windowMs) {
  let found = null;
  for (const [id, session] of Object.entries(sessions ?? {})) {
    const isRecent = now - session.lastActiveAt < windowMs;
    if (isRecent && (!found || session.lastActiveAt > found[1].lastActiveAt)) {
      found = [id, session];
    }
  }
  return found;
}

export function aiTabSwitchEvent(host, nowIso = new Date().toISOString()) {
  return { type: "ai_tab_switch", payload: { host }, occurredAt: nowIso };
}

/**
 * Add events to a tab's upload bucket. Buckets belong to the account that was
 * signed in when the events were captured; a different account starts a fresh
 * bucket so nothing captured for one student is ever uploaded as another.
 */
export function addToBucket(pending, tabId, { sessionId, ownerId, events, maxEvents }) {
  let bucket = pending[tabId];
  if (!bucket || bucket.ownerId !== ownerId) {
    bucket = { sessionId, ownerId, events: [] };
  }
  bucket.events.push(...events);
  if (bucket.events.length > maxEvents) {
    bucket.events = bucket.events.slice(-maxEvents);
  }
  pending[tabId] = bucket;
  return bucket;
}

/* ---------- batches and signing ---------- */

export function buildBatch({ studentId, assignmentId, sessionId, events, now, uuid }) {
  const makeId = uuid ?? (() => crypto.randomUUID());
  const createdAt = (now ?? new Date()).toISOString();
  return {
    batchId: makeId(),
    studentId,
    assignmentId,
    createdAt,
    events: events.map((event) => ({
      id: makeId(),
      sessionId,
      assignmentId,
      studentId,
      type: event.type,
      occurredAt: event.occurredAt ?? createdAt,
      payload: event.payload ?? {},
    })),
  };
}

/** The exact JSON the API re-serialises and verifies (key order matters). */
export function canonicalBatch(batch) {
  return JSON.stringify({
    batchId: batch.batchId,
    studentId: batch.studentId,
    assignmentId: batch.assignmentId,
    createdAt: batch.createdAt,
    events: batch.events,
  });
}

export function b64url(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** True when the stored install key cannot produce a verifiable upload (older
 *  versions stored the "public" JWK without its `k`, so every batch failed). */
export function needsNewSigningKey(stored) {
  const usable = (jwk) => jwk?.kty === "oct" && typeof jwk.k === "string" && jwk.k.length > 0;
  return !usable(stored?.privateKey) || !usable(stored?.publicKey);
}

export async function generateSigningJwk(subtle = crypto.subtle) {
  const key = await subtle.generateKey({ name: "HMAC", hash: "SHA-256" }, true, [
    "sign",
    "verify",
  ]);
  return subtle.exportKey("jwk", key);
}

/** Sign a batch the way the API verifies it: HMAC-SHA256 over canonicalBatch,
 *  base64url, plus the full exported JWK (HMAC is symmetric, so the server
 *  needs `k`; identity still comes from the bearer token). */
export async function signBatch(batch, jwk, subtle = crypto.subtle) {
  const key = await subtle.importKey("jwk", jwk, { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
  const data = new TextEncoder().encode(canonicalBatch(batch));
  const signature = await subtle.sign("HMAC", key, data);
  return {
    ...batch,
    clientSignature: b64url(new Uint8Array(signature)),
    clientPublicKey: JSON.stringify(jwk),
  };
}

/* ---------- upload outcomes ---------- */

/**
 * What to do with a queued batch after an upload attempt.
 *  ok      - accepted (202, or an idempotent replay)
 *  reauth  - the bearer token was rejected: keep the batch, ask to sign in
 *  resign  - the signature was rejected: new key, try again (bounded)
 *  drop    - permanently rejected (unknown assignment, someone else's batch...)
 *  retry   - transient (network, 408, 429, 5xx): back off
 */
export function classifyUploadResponse(status, code) {
  if (status === 0) {
    return "retry";
  }
  if (status >= 200 && status < 300) {
    return "ok";
  }
  if (status === 401) {
    return "reauth";
  }
  if (status === 400 && code === "INVALID_SIGNATURE") {
    return "resign";
  }
  if (status === 408 || status === 429 || status >= 500) {
    return "retry";
  }
  return "drop";
}

export function retryDelayMs(attempts) {
  return Math.min(RETRY_BASE_MS * 2 ** attempts, RETRY_MAX_MS);
}

/** The first queued batch the signed-in student owns, if it is due. Batches of
 *  other accounts stay queued until that account signs in again. */
export function nextUploadable(queue, studentId, now) {
  const item = queue.find((entry) => entry.batch.studentId === studentId);
  if (!item || item.nextAttemptAt > now) {
    return null;
  }
  return item;
}

export function queueStats(queue, studentId) {
  const own = queue.filter((entry) => entry.batch.studentId === studentId);
  return {
    pendingBatches: own.length,
    pendingEvents: own.reduce((sum, entry) => sum + entry.batch.events.length, 0),
  };
}

/* ---------- concurrency ---------- */

/**
 * A promise-chain mutex. Every chrome.storage read-modify-write in the worker
 * runs inside one, so concurrent messages, alarms and uploads cannot lose or
 * duplicate events. Not re-entrant: never call the lock from inside itself.
 */
export function createLock() {
  let tail = Promise.resolve();
  return function withLock(task) {
    const run = tail.then(() => task());
    tail = run.catch(() => {});
    return run;
  };
}

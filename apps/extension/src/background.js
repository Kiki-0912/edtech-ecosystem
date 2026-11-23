// Integrity Lens service worker (MV3, ES module). Pure logic lives in lib.js so
// apps/api/test/telemetry-extension.test.ts can exercise it in Node.
//
// Rules this file keeps:
//  - Nothing is recorded or uploaded before consent.
//  - Every chrome.storage read-modify-write runs inside withLock, so concurrent
//    messages, alarms and uploads cannot lose or duplicate events.
//  - Timers are chrome.alarms: in-memory timers die with the suspended worker.
import {
  MAX_SIGNATURE_FAILURES,
  addToBucket,
  aiTabSwitchEvent,
  applyEvents,
  buildBatch,
  classifyUploadResponse,
  computeScore,
  createLock,
  effectiveOrigins,
  emptySession,
  generateSigningJwk,
  hostFromUrl,
  isAiHost,
  isMonitoredUrl,
  latestActiveSession,
  needsNewSigningKey,
  nextUploadable,
  normalizeBaseUrl,
  originMatchPattern,
  queueStats,
  retryDelayMs,
  sanitizeContentEvents,
  signBatch,
  DEFAULT_API_BASE_URL,
} from "./lib.js";

const SESSIONS_KEY = "sessions";
const PENDING_EVENTS_KEY = "pendingEvents";
const QUEUE_KEY = "uploadQueue";
const STATUS_KEY = "syncStatus";
const AUTH_KEY = "auth";
const INSTALL_KEY = "installKey";

// chrome.storage.sync holds user-facing settings so they roam with the profile.
const SETTINGS_KEY = "settings";

const RECENT_WINDOW_MS = 30 * 60 * 1000;
const MAX_PENDING_BATCHES = 200;
const MAX_QUEUE_EVENTS = 5_000;

const FLUSH_ALARM = "flush";
const RETRY_ALARM = "retry";
// One minute is the smallest period every supported Chrome honours.
const FLUSH_PERIOD_MINUTES = 1;

const CONTENT_SCRIPT_ID = "integrity-lens-capture";

/** Storage read-modify-write lock (see lib.js createLock). Not re-entrant. */
const withLock = createLock();
/** One upload run at a time, so a batch is never in flight twice. */
const withUploadLock = createLock();
/** Serialises content-script (un)registration. */
const withScriptLock = createLock();

/* ---------- storage helpers (raw; mutate only inside withLock) ---------- */

async function loadSessions() {
  const stored = await chrome.storage.session.get(SESSIONS_KEY);
  return stored[SESSIONS_KEY] ?? {};
}

async function saveSessions(sessions) {
  await chrome.storage.session.set({ [SESSIONS_KEY]: sessions });
}

async function getSettings() {
  const stored = await chrome.storage.sync.get(SETTINGS_KEY);
  const settings = stored[SETTINGS_KEY] ?? {};
  return {
    apiBaseUrl: normalizeBaseUrl(settings.apiBaseUrl ?? DEFAULT_API_BASE_URL),
    consentEnabled: Boolean(settings.consentEnabled),
    allowedOrigins: settings.allowedOrigins,
  };
}

async function getAuth() {
  const stored = await chrome.storage.local.get(AUTH_KEY);
  const auth = stored[AUTH_KEY] ?? {};
  return {
    token: typeof auth.token === "string" ? auth.token : null,
    studentId: typeof auth.studentId === "string" ? auth.studentId : null,
    studentName: typeof auth.studentName === "string" ? auth.studentName : null,
  };
}

async function loadPendingEvents() {
  const stored = await chrome.storage.session.get(PENDING_EVENTS_KEY);
  return stored[PENDING_EVENTS_KEY] ?? {};
}

async function savePendingEvents(pending) {
  await chrome.storage.session.set({ [PENDING_EVENTS_KEY]: pending });
}

async function loadQueue() {
  const stored = await chrome.storage.local.get(QUEUE_KEY);
  return stored[QUEUE_KEY] ?? [];
}

async function saveQueue(queue) {
  await chrome.storage.local.set({ [QUEUE_KEY]: queue });
}

async function patchStatus(patch) {
  const stored = await chrome.storage.session.get(STATUS_KEY);
  const status = { ...(stored[STATUS_KEY] ?? {}), ...patch, updatedAt: Date.now() };
  await chrome.storage.session.set({ [STATUS_KEY]: status });
  return status;
}

function updateStatus(patch) {
  return withLock(() => patchStatus(patch));
}

/* ---------- HMAC signing key (one per install) ---------- */

/** The install's HMAC JWK, regenerated when the stored one cannot sign a
 *  verifiable batch (older versions stored the public JWK without `k`). */
function getSigningJwk({ rotate = false } = {}) {
  return withLock(async () => {
    const stored = (await chrome.storage.local.get(INSTALL_KEY))[INSTALL_KEY];
    if (!rotate && !needsNewSigningKey(stored)) {
      return stored.publicKey;
    }
    const jwk = await generateSigningJwk();
    // HMAC is symmetric: the server needs the full key (with `k`) to verify.
    // Identity still comes from the bearer token, not from this key.
    await chrome.storage.local.set({ [INSTALL_KEY]: { privateKey: jwk, publicKey: jwk } });
    return jwk;
  });
}

/* ---------- telemetry ingestion from content scripts ---------- */

async function handleTelemetry(message, sender) {
  const tabId = sender.tab?.id;
  if (tabId === undefined || sender.id !== chrome.runtime.id) {
    return { ok: false, reason: "no-tab" };
  }

  const settings = await getSettings();
  if (!settings.consentEnabled) {
    return { ok: false, disabled: true };
  }

  const auth = await getAuth();
  const origins = effectiveOrigins(settings);
  const events = sanitizeContentEvents(message.events);
  const tabUrl = sender.tab.url ?? "";

  return withLock(async () => {
    const sessions = await loadSessions();
    const session = sessions[tabId] ?? emptySession(tabId, tabUrl);
    session.url = tabUrl || session.url;
    if (typeof message.sessionId === "string" && message.sessionId) {
      session.sessionId = message.sessionId;
    }

    // Only a configured LMS origin may attach a session to an assignment;
    // anything else stays local and is never uploaded.
    if (!isMonitoredUrl(session.url, origins)) {
      session.assignmentId = null;
    } else if (
      typeof message.assignmentId === "string" &&
      message.assignmentId &&
      message.assignmentId !== "unassigned"
    ) {
      session.assignmentId = message.assignmentId;
    }

    applyEvents(session, events);
    sessions[tabId] = session;
    await saveSessions(sessions);

    // Buffer raw events for batch upload, tagged with the signed-in account.
    const pending = await loadPendingEvents();
    addToBucket(pending, tabId, {
      sessionId: session.sessionId,
      ownerId: auth.studentId,
      events,
      maxEvents: MAX_QUEUE_EVENTS,
    });
    await savePendingEvents(pending);

    return { ok: true, score: session.score };
  });
}

/* ---------- batch construction and upload ---------- */

/** Turn pending buckets owned by the signed-in student into queued batches. */
async function enqueueBatches(settings, auth) {
  const origins = effectiveOrigins(settings);
  const pending = await loadPendingEvents();
  const sessions = await loadSessions();
  const queue = await loadQueue();

  for (const [tabId, bucket] of Object.entries(pending)) {
    if (!bucket?.events?.length) {
      delete pending[tabId];
      continue;
    }
    // Captured under another account (or signed out): never upload it as
    // this student. It stays partitioned until its owner signs in again.
    if (bucket.ownerId !== auth.studentId) {
      continue;
    }

    const session = sessions[tabId];
    const assignmentId = session?.assignmentId ?? null;
    if (!assignmentId || !isMonitoredUrl(session.url, origins)) {
      // Sessions not attached to an assignment stay local only.
      continue;
    }

    const batch = buildBatch({
      studentId: auth.studentId,
      assignmentId,
      sessionId: bucket.sessionId,
      events: bucket.events,
    });
    queue.push({ batch, attempts: 0, nextAttemptAt: 0, signatureFailures: 0 });
    delete pending[tabId];
  }

  if (queue.length > MAX_PENDING_BATCHES) {
    queue.splice(0, queue.length - MAX_PENDING_BATCHES);
  }

  await savePendingEvents(pending);
  await saveQueue(queue);
  await patchStatus({
    consentEnabled: true,
    ...queueStats(queue, auth.studentId),
    loggedIn: true,
    studentName: auth.studentName,
  });
}

async function flushToApi() {
  const settings = await getSettings();
  if (!settings.consentEnabled) {
    return;
  }

  const auth = await getAuth();
  if (!auth.token || !auth.studentId) {
    return;
  }

  await withLock(() => enqueueBatches(settings, auth));
  await withUploadLock(() => uploadReadyBatches(settings, auth));
}

/** Record an upload outcome on the queued batch. Returns true to stop the run. */
async function applyOutcome(batchId, outcome, status, auth) {
  const queue = await loadQueue();
  const index = queue.findIndex((entry) => entry.batch.batchId === batchId);
  const item = index === -1 ? null : queue[index];
  let stop = false;
  const patch = {};

  if (outcome === "ok") {
    if (item) {
      queue.splice(index, 1);
    }
    Object.assign(patch, { lastUploadAt: Date.now(), lastError: null, needsReauth: false });
  } else if (outcome === "reauth") {
    Object.assign(patch, { needsReauth: true, lastError: "Session expired, sign in again" });
    stop = true;
  } else if (outcome === "resign") {
    if (item) {
      item.signatureFailures = (item.signatureFailures ?? 0) + 1;
      if (item.signatureFailures > MAX_SIGNATURE_FAILURES) {
        queue.splice(index, 1);
        patch.lastError = "Batch dropped: signature rejected";
      }
    }
  } else if (outcome === "drop") {
    if (item) {
      queue.splice(index, 1);
    }
    patch.lastError = `Batch rejected (${status})`;
  } else {
    if (item) {
      item.attempts += 1;
      item.nextAttemptAt = Date.now() + retryDelayMs(item.attempts);
    }
    patch.lastError = status === 0 ? "API unreachable, will retry" : `Server error (${status})`;
    stop = true;
  }

  await saveQueue(queue);
  await patchStatus({ ...patch, ...queueStats(queue, auth.studentId) });
  return stop;
}

async function uploadReadyBatches(settings, auth) {
  let jwk = null;
  let rotate = false;

  for (;;) {
    const item = await withLock(async () =>
      nextUploadable(await loadQueue(), auth.studentId, Date.now()),
    );
    if (!item) {
      break;
    }

    if (!jwk) {
      jwk = await getSigningJwk({ rotate });
      rotate = false;
    }
    const body = await signBatch(item.batch, jwk);

    let status = 0;
    let code = null;
    try {
      const response = await fetch(`${settings.apiBaseUrl}/api/v1/telemetry/batches`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${auth.token}`,
        },
        body: JSON.stringify(body),
      });
      status = response.status;
      if (!response.ok) {
        code = (await response.json().catch(() => null))?.error?.code ?? null;
      }
    } catch {
      status = 0;
    }

    const outcome = classifyUploadResponse(status, code);
    if (outcome === "resign") {
      // The server could not verify our key: mint a fresh one and retry
      // (bounded per batch by MAX_SIGNATURE_FAILURES).
      jwk = null;
      rotate = true;
    }
    const stop = await withLock(() => applyOutcome(item.batch.batchId, outcome, status, auth));
    if (stop) {
      break;
    }
  }

  await scheduleRetry(auth);
}

/** A one-shot alarm at the earliest backoff deadline (the periodic flush
 *  alarm is the safety net if Chrome clamps it). */
async function scheduleRetry(auth) {
  const queue = await loadQueue();
  const now = Date.now();
  const due = queue
    .filter((entry) => entry.batch.studentId === auth.studentId && entry.nextAttemptAt > now)
    .map((entry) => entry.nextAttemptAt);
  if (due.length === 0) {
    await chrome.alarms.clear(RETRY_ALARM);
    return;
  }
  await chrome.alarms.create(RETRY_ALARM, { when: Math.min(...due) });
}

/* ---------- monitored origins: content-script registration ---------- */

/** Inject the capture scripts only on configured LMS origins the student has
 *  granted host access to (optional_host_permissions). */
function syncContentScripts() {
  return withScriptLock(async () => {
    const settings = await getSettings();
    const matches = [];
    for (const origin of effectiveOrigins(settings)) {
      const pattern = originMatchPattern(origin);
      if (await chrome.permissions.contains({ origins: [pattern] })) {
        matches.push(pattern);
      }
    }

    const existing = await chrome.scripting.getRegisteredContentScripts({
      ids: [CONTENT_SCRIPT_ID],
    });
    if (existing.length > 0) {
      await chrome.scripting.unregisterContentScripts({ ids: [CONTENT_SCRIPT_ID] });
    }
    if (matches.length === 0) {
      return;
    }
    await chrome.scripting.registerContentScripts([
      {
        id: CONTENT_SCRIPT_ID,
        matches,
        // privacy.js defines the sensitive-target filter content.js relies on.
        js: ["src/privacy.js", "src/content.js"],
        runAt: "document_idle",
        persistAcrossSessions: true,
      },
    ]);
  });
}

/* ---------- runtime messages ---------- */

async function syncStatus() {
  const [sessionStored, settings, auth, queue] = await Promise.all([
    chrome.storage.session.get(STATUS_KEY),
    getSettings(),
    getAuth(),
    loadQueue(),
  ]);
  return {
    ...(sessionStored[STATUS_KEY] ?? {}),
    consentEnabled: settings.consentEnabled,
    loggedIn: Boolean(auth.token && auth.studentId),
    studentName: auth.studentName,
    ...queueStats(queue, auth.studentId),
  };
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type === "telemetry") {
    handleTelemetry(message, sender)
      .then(sendResponse)
      .catch(() => sendResponse({ ok: false }));
    return true;
  }

  if (message?.type === "get-consent") {
    getSettings().then((settings) => sendResponse({ enabled: settings.consentEnabled }));
    return true;
  }

  if (message?.type === "get-session") {
    loadSessions().then((sessions) => sendResponse({ session: sessions[message.tabId] ?? null }));
    return true;
  }

  if (message?.type === "get-sync-status") {
    syncStatus().then((status) => sendResponse({ status }));
    return true;
  }

  if (message?.type === "flush-now") {
    // The options "Upload now" button: run a full flush, then report status.
    flushToApi()
      .catch(() => {})
      .then(syncStatus)
      .then((status) => sendResponse({ status }));
    return true;
  }

  if (message?.type === "reset-session") {
    withLock(async () => {
      const sessions = await loadSessions();
      delete sessions[message.tabId];
      await saveSessions(sessions);
      const pending = await loadPendingEvents();
      delete pending[message.tabId];
      await savePendingEvents(pending);
    }).then(() => sendResponse({ ok: true }));
    return true;
  }

  return false;
});

/* ---------- AI tab-switch tracking ---------- */

chrome.tabs.onActivated.addListener(async ({ tabId }) => {
  try {
    const settings = await getSettings();
    if (!settings.consentEnabled) {
      return;
    }

    const tab = await chrome.tabs.get(tabId);
    const host = tab.url ? hostFromUrl(tab.url) : null;
    if (!host || !isAiHost(host)) {
      return;
    }

    const auth = await getAuth();
    await withLock(async () => {
      const sessions = await loadSessions();
      const now = Date.now();
      const found = latestActiveSession(sessions, now, RECENT_WINDOW_MS);
      if (!found) {
        return;
      }

      const [targetId, session] = found;
      session.aiTabSwitches += 1;
      session.lastAiHost = host;
      session.score = computeScore(session);
      session.updatedAt = now;
      sessions[targetId] = session;
      await saveSessions(sessions);

      // Queue it for upload too, so server scoring and flags see the switch.
      const pending = await loadPendingEvents();
      addToBucket(pending, targetId, {
        sessionId: session.sessionId,
        ownerId: auth.studentId,
        events: [aiTabSwitchEvent(host)],
        maxEvents: MAX_QUEUE_EVENTS,
      });
      await savePendingEvents(pending);
    });
  } catch {
    return;
  }
});

chrome.tabs.onRemoved.addListener((tabId) => {
  // Flush whatever the closing tab buffered before forgetting it.
  flushToApi()
    .catch(() => {})
    .then(() =>
      withLock(async () => {
        const sessions = await loadSessions();
        if (sessions[tabId]) {
          delete sessions[tabId];
          await saveSessions(sessions);
        }
        const pending = await loadPendingEvents();
        if (pending[tabId]) {
          delete pending[tabId];
          await savePendingEvents(pending);
        }
      }),
    )
    .catch(() => {});
});

/* ---------- lifecycle ---------- */

async function ensureFlushAlarm() {
  const existing = await chrome.alarms.get(FLUSH_ALARM);
  if (!existing) {
    await chrome.alarms.create(FLUSH_ALARM, { periodInMinutes: FLUSH_PERIOD_MINUTES });
  }
}

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === FLUSH_ALARM || alarm.name === RETRY_ALARM) {
    flushToApi().catch(() => {});
  }
});

chrome.runtime.onInstalled.addListener(() => {
  // First-run and updates open settings so the student can review consent.
  chrome.runtime.openOptionsPage();
  syncContentScripts().catch(() => {});
});

chrome.runtime.onStartup.addListener(() => {
  syncContentScripts().catch(() => {});
});

chrome.permissions.onAdded.addListener(() => {
  syncContentScripts().catch(() => {});
});

chrome.permissions.onRemoved.addListener(() => {
  syncContentScripts().catch(() => {});
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "sync" && changes[SETTINGS_KEY]) {
    syncContentScripts().catch(() => {});
    flushToApi().catch(() => {});
  }

  if (area === "local" && changes[AUTH_KEY]) {
    const next = changes[AUTH_KEY].newValue;
    if (next?.token && next?.studentId) {
      // A fresh sign-in ends any "session expired" state, then uploads the
      // new account's own queued batches (others stay partitioned).
      updateStatus({ needsReauth: false, lastError: null, loggedIn: true })
        .then(flushToApi)
        .catch(() => {});
    } else {
      updateStatus({ needsReauth: false, loggedIn: false, studentName: null }).catch(() => {});
    }
  }
});

// Every worker start (install, browser start, wake-up) makes sure the periodic
// flush alarm exists. Alarms, unlike setInterval, survive worker suspension, so
// nothing relies on onSuspend (an async fetch there would never complete).
ensureFlushAlarm().catch(() => {});

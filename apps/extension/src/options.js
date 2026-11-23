import {
  DEFAULT_API_BASE_URL,
  effectiveOrigins,
  normalizeBaseUrl,
  normalizeOrigin,
  originMatchPattern,
  parseOrigins,
} from "./lib.js";

const SETTINGS_KEY = "settings";
const AUTH_KEY = "auth";

const elements = {
  apiUrl: document.getElementById("api-url"),
  loginId: document.getElementById("login-id"),
  loginPassword: document.getElementById("login-password"),
  login: document.getElementById("login"),
  logout: document.getElementById("logout"),
  testConnection: document.getElementById("test-connection"),
  accountStatus: document.getElementById("account-status"),
  consent: document.getElementById("consent"),
  consentStatus: document.getElementById("consent-status"),
  statPending: document.getElementById("stat-pending"),
  statEvents: document.getElementById("stat-events"),
  statLastUpload: document.getElementById("stat-last-upload"),
  statError: document.getElementById("stat-error"),
  flush: document.getElementById("flush"),
  allowedOrigins: document.getElementById("allowed-origins"),
  saveOrigins: document.getElementById("save-origins"),
  originsStatus: document.getElementById("origins-status"),
};

/**
 * Ask for host access to these origins. chrome.permissions.request needs the
 * click's user gesture, so call this synchronously at the top of a handler,
 * before any await. Resolves to the origins that ended up granted.
 */
function requestOrigins(origins) {
  const patterns = origins.map(originMatchPattern);
  if (patterns.length === 0) {
    return Promise.resolve([]);
  }
  return chrome.permissions
    .request({ origins: patterns })
    .catch(() => false)
    .then(async (granted) => {
      if (granted) {
        return origins;
      }
      const kept = [];
      for (const origin of origins) {
        if (await chrome.permissions.contains({ origins: [originMatchPattern(origin)] })) {
          kept.push(origin);
        }
      }
      return kept;
    });
}

/** Host access for the API itself (needed for uploads and /health). */
function requestApiAccess(base) {
  const origin = normalizeOrigin(base);
  return origin ? requestOrigins([origin]) : Promise.resolve([]);
}

function setStatus(element, text, kind) {
  element.textContent = text;
  element.classList.remove("ok", "err");
  if (kind) {
    element.classList.add(kind);
  }
}

async function loadState() {
  const [syncStored, localStored] = await Promise.all([
    chrome.storage.sync.get(SETTINGS_KEY),
    chrome.storage.local.get(AUTH_KEY),
  ]);
  const settings = syncStored[SETTINGS_KEY] ?? {};
  const auth = localStored[AUTH_KEY] ?? {};

  elements.apiUrl.value = settings.apiBaseUrl ?? DEFAULT_API_BASE_URL;
  elements.allowedOrigins.value = Array.isArray(settings.allowedOrigins)
    ? settings.allowedOrigins.join("\n")
    : "";
  setStatus(
    elements.originsStatus,
    `Monitoring: ${effectiveOrigins(settings).join(", ") || "no sites"}`,
    null,
  );
  elements.consent.checked = Boolean(settings.consentEnabled);

  if (auth.studentName) {
    setStatus(
      elements.accountStatus,
      `Signed in as ${auth.studentName}`,
      "ok",
    );
  } else {
    setStatus(elements.accountStatus, "Not signed in.", null);
  }
  if (elements.consent.checked) {
    setStatus(elements.consentStatus, "Monitoring is enabled.", "ok");
  } else {
    setStatus(elements.consentStatus, "Monitoring is off. Sessions stay local only.", null);
  }
}

async function saveSettings(patch) {
  const stored = await chrome.storage.sync.get(SETTINGS_KEY);
  const settings = { ...(stored[SETTINGS_KEY] ?? {}), ...patch };
  await chrome.storage.sync.set({ [SETTINGS_KEY]: settings });
  return settings;
}

elements.testConnection.addEventListener("click", async () => {
  const base = normalizeBaseUrl(elements.apiUrl.value);
  const access = requestApiAccess(base);
  setStatus(elements.accountStatus, "Testing connection…", null);
  try {
    await access;
    const response = await fetch(`${base}/health`, { method: "GET" });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const health = await response.json();
    setStatus(
      elements.accountStatus,
      `Connected to ${health.service ?? "API"} (${health.version ?? "unknown version"}).`,
      "ok",
    );
  } catch (error) {
    setStatus(
      elements.accountStatus,
      `Could not reach the API: ${error.message}. Is it running?`,
      "err",
    );
  }
});

elements.login.addEventListener("click", async () => {
  const base = normalizeBaseUrl(elements.apiUrl.value);
  const access = requestApiAccess(base);
  const loginId = elements.loginId.value.trim();
  const password = elements.loginPassword.value;

  if (!loginId || !password) {
    setStatus(elements.accountStatus, "Enter your phone/email and password.", "err");
    return;
  }

  setStatus(elements.accountStatus, "Signing in…", null);
  try {
    await access;
    const isEmail = loginId.includes("@");
    const response = await fetch(`${base}/api/v1/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(
        isEmail ? { email: loginId, password } : { phone: loginId, password },
      ),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(payload?.error?.message ?? `HTTP ${response.status}`);
    }

    // The background worker sees this change, clears any "session expired"
    // state and uploads this account's own queued batches.
    await chrome.storage.local.set({
      [AUTH_KEY]: {
        token: payload.data.token,
        studentId: payload.data.user.id,
        studentName: payload.data.user.displayName,
      },
    });
    await saveSettings({ apiBaseUrl: base });
    setStatus(
      elements.accountStatus,
      `Signed in as ${payload.data.user.displayName}.`,
      "ok",
    );
    elements.loginPassword.value = "";
  } catch (error) {
    setStatus(elements.accountStatus, `Sign-in failed: ${error.message}`, "err");
  }
});

elements.logout.addEventListener("click", async () => {
  await chrome.storage.local.remove(AUTH_KEY);
  setStatus(elements.accountStatus, "Signed out. Queued data stays with this account and uploads only after it signs in again.", null);
});

elements.consent.addEventListener("change", async () => {
  await saveSettings({ consentEnabled: elements.consent.checked });
  if (elements.consent.checked) {
    setStatus(elements.consentStatus, "Monitoring is enabled.", "ok");
  } else {
    setStatus(
      elements.consentStatus,
      "Monitoring is off. New typing is no longer recorded or uploaded.",
      null,
    );
  }
});

elements.flush.addEventListener("click", async () => {
  elements.flush.disabled = true;
  try {
    // Runs a full flush in the service worker and waits for it to finish.
    await chrome.runtime.sendMessage({ type: "flush-now" });
  } catch {
    // Status below shows whatever the worker recorded.
  } finally {
    elements.flush.disabled = false;
    await refreshStats();
  }
});

elements.saveOrigins.addEventListener("click", async () => {
  const wanted = parseOrigins(elements.allowedOrigins.value);
  // Before any await: the permission prompt needs this click's gesture.
  const access = requestOrigins(wanted);
  const granted = await access;
  // An empty list means "use the API origin" (the default).
  const settings = await saveSettings({ allowedOrigins: granted.length ? granted : undefined });
  elements.allowedOrigins.value = granted.join("\n");
  const skipped = wanted.filter((origin) => !granted.includes(origin));
  setStatus(
    elements.originsStatus,
    skipped.length
      ? `Access not granted for ${skipped.join(", ")}. Monitoring: ${effectiveOrigins(settings).join(", ")}`
      : `Monitoring: ${effectiveOrigins(settings).join(", ") || "no sites"}`,
    skipped.length ? "err" : "ok",
  );
});

async function refreshStats() {
  try {
    const response = await chrome.runtime.sendMessage({ type: "get-sync-status" });
    const status = response?.status ?? {};
    elements.statPending.textContent = String(status.pendingBatches ?? 0);
    elements.statEvents.textContent = String(status.pendingEvents ?? 0);
    elements.statLastUpload.textContent = status.lastUploadAt
      ? new Date(status.lastUploadAt).toLocaleTimeString()
      : "Never";
    elements.statError.textContent = status.lastError ?? "None";
    if (status.needsReauth) {
      setStatus(elements.accountStatus, "Session expired — sign in again.", "err");
    }
  } catch {
    elements.statPending.textContent = "–";
  }
}

elements.apiUrl.addEventListener("change", async () => {
  await saveSettings({ apiBaseUrl: normalizeBaseUrl(elements.apiUrl.value) });
});

loadState().then(refreshStats);
setInterval(refreshStats, 3000);

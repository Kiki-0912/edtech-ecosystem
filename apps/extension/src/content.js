(() => {
  const SESSION_ID = crypto.randomUUID();
  const FLUSH_INTERVAL_MS = 2000;
  const CURSOR_SAMPLE_MS = 500;
  const MODIFIER_KEYS = new Set([
    "Shift",
    "Control",
    "Alt",
    "Meta",
    "CapsLock",
    "Escape",
    "Tab",
    "ArrowUp",
    "ArrowDown",
    "ArrowLeft",
    "ArrowRight",
  ]);

  const metaAssignment = document.querySelector('meta[name="edtech-assignment-id"]');
  const assignmentId =
    new URLSearchParams(window.location.search).get("assignmentId") ||
    metaAssignment?.getAttribute("content") ||
    "unassigned";

  let queue = [];
  let lastKeyAt = 0;
  let lastCursorAt = 0;
  let lastCursorX = null;
  let lastCursorY = null;
  let consentEnabled = false;

  // Capture only runs when the student has enabled monitoring in settings.
  try {
    chrome.runtime.sendMessage({ type: "get-consent" }, (response) => {
      consentEnabled = Boolean(response?.enabled);
    });
  } catch {
    consentEnabled = false;
  }

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "sync" && changes.settings) {
      consentEnabled = Boolean(changes.settings.newValue?.consentEnabled);
      if (!consentEnabled) {
        queue = [];
      }
    }
  });

  // From privacy.js, injected first. Without it, treat everything as sensitive.
  const isSensitiveEvent =
    globalThis.IntegrityLensPrivacy?.isSensitiveEvent ?? (() => true);

  function enqueue(type, payload) {
    if (!consentEnabled) {
      return;
    }
    queue.push({
      type,
      payload,
      occurredAt: new Date().toISOString(),
    });
  }

  function flush() {
    if (queue.length === 0) {
      return;
    }

    const events = queue;
    queue = [];
    try {
      chrome.runtime.sendMessage({
        type: "telemetry",
        sessionId: SESSION_ID,
        assignmentId,
        events,
      });
    } catch {
      return;
    }
  }

  // Each document is captured once: by its own copy of this script, or by a
  // parent frame's copy for same-origin about:blank frames (Google Docs types
  // into one) where the browser may not inject scripts. A DOM marker, visible
  // to every copy, prevents double counting.
  const CAPTURE_MARK = "data-integrity-lens";

  function claim(doc) {
    const root = doc?.documentElement;
    if (!root || root.hasAttribute(CAPTURE_MARK)) {
      return false;
    }
    root.setAttribute(CAPTURE_MARK, "");
    return true;
  }

  function attach(win) {
    win.addEventListener(
      "keydown",
      (event) => {
        if (event.isComposing || MODIFIER_KEYS.has(event.key) || isSensitiveEvent(event)) {
          return;
        }

        const now = performance.now();
        const deltaMs = lastKeyAt === 0 ? 0 : Math.round(now - lastKeyAt);
        lastKeyAt = now;
        enqueue("keystroke", { deltaMs });
      },
      true,
    );

    win.addEventListener(
      "paste",
      (event) => {
        if (isSensitiveEvent(event)) {
          return;
        }

        const text = event.clipboardData?.getData("text") ?? "";
        enqueue("paste", { characterCount: text.length });
      },
      true,
    );

    win.addEventListener(
      "mousemove",
      (event) => {
        if (!consentEnabled) {
          return;
        }
        if (isSensitiveEvent(event)) {
          // Forget the last point so no distance is measured across the region.
          lastCursorX = null;
          lastCursorY = null;
          return;
        }

        const now = performance.now();
        if (now - lastCursorAt < CURSOR_SAMPLE_MS) {
          return;
        }

        if (lastCursorX !== null && lastCursorY !== null) {
          const distance = Math.round(
            Math.hypot(event.clientX - lastCursorX, event.clientY - lastCursorY),
          );
          enqueue("cursor", { distancePx: distance });
        }

        lastCursorAt = now;
        lastCursorX = event.clientX;
        lastCursorY = event.clientY;
      },
      { capture: true, passive: true },
    );
  }

  /** Capture same-origin child frames that have no script of their own. */
  function attachFrames(doc) {
    for (const frame of doc.querySelectorAll("iframe, frame")) {
      try {
        const childDoc = frame.contentDocument;
        if (childDoc && claim(childDoc)) {
          attach(frame.contentWindow);
          attachFrames(childDoc);
        }
      } catch {
        // Cross-origin frame: not ours to read.
      }
    }
  }

  if (claim(document)) {
    attach(window);
  }
  attachFrames(document);
  new MutationObserver(() => attachFrames(document)).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
  // A frame's blank document can be replaced after load; re-check periodically.
  setInterval(() => attachFrames(document), 3000);

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
      flush();
    }
  });

  window.addEventListener("pagehide", flush);

  setInterval(flush, FLUSH_INTERVAL_MS);
})();

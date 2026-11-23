// Privacy filter shared by the content script (loaded before content.js in the
// same isolated world) and the Node unit test. Classic script: no import/export.
(() => {
  /** Event path that pierces open shadow roots; falls back to the target. */
  function eventPath(event) {
    const path = typeof event?.composedPath === "function" ? event.composedPath() : [];
    return path.length > 0 ? path : [event?.target];
  }

  function isElement(node) {
    return Boolean(node) && node.nodeType === 1 && typeof node.getAttribute === "function";
  }

  /**
   * True when an event must not be recorded: the real target (path[0], inside
   * any shadow root) is a password or hidden input, or it or any ancestor
   * (across shadow boundaries, which closest() cannot cross) is marked
   * [data-sensitive]. The [data-sensitive] check runs for every element type.
   */
  function isSensitivePath(path) {
    for (const node of path) {
      if (isElement(node) && node.hasAttribute("data-sensitive")) {
        return true;
      }
    }

    const target = path[0];
    if (isElement(target) && String(target.tagName).toUpperCase() === "INPUT") {
      const type = (target.getAttribute("type") || "text").toLowerCase();
      return type === "password" || type === "hidden";
    }
    return false;
  }

  globalThis.IntegrityLensPrivacy = {
    eventPath,
    isSensitivePath,
    isSensitiveEvent: (event) => isSensitivePath(eventPath(event)),
  };
})();

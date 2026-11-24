// Pure helpers behind linking documents (e.g. Google Docs) to assignments.
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { documentKey, resolveAssignment } from "../../extension/src/lib.js";

describe("documentKey", () => {
  test("one Google Doc maps to one key across edit/view/account URLs", () => {
    const key = "https://docs.google.com/document/d/abc123";
    assert.equal(documentKey("https://docs.google.com/document/d/abc123/edit?tab=t.0#h"), key);
    assert.equal(documentKey("https://docs.google.com/document/u/1/d/abc123/view"), key);
    assert.notEqual(documentKey("https://docs.google.com/document/d/other/edit"), key);
    assert.equal(
      documentKey("https://docs.google.com/spreadsheets/d/s1/edit"),
      "https://docs.google.com/spreadsheets/d/s1",
    );
  });

  test("other pages use origin + path, without query or trailing slash", () => {
    assert.equal(documentKey("https://lms.example/essay/7/?x=1"), "https://lms.example/essay/7");
    assert.equal(documentKey("about:blank"), null);
    assert.equal(documentKey("not a url"), null);
  });
});

describe("resolveAssignment", () => {
  const docKey = "https://docs.google.com/document/d/abc123";
  const link = { assignmentId: "a-002", title: "Essay", ownerId: "u-student-1" };

  test("unmonitored sites never get an assignment", () => {
    assert.deepEqual(
      resolveAssignment({ monitored: false, link, pageAssignmentId: "a-001", docKey }),
      { assignmentId: null, linkedDocKey: null },
    );
  });

  test("a link picked in the popup wins over the page's assignmentId", () => {
    assert.deepEqual(
      resolveAssignment({ monitored: true, link, pageAssignmentId: "a-001", docKey }),
      { assignmentId: "a-002", linkedDocKey: docKey },
    );
  });

  test("falls back to the page's assignmentId, ignoring 'unassigned'", () => {
    assert.equal(
      resolveAssignment({ monitored: true, link: null, pageAssignmentId: "a-001", docKey })
        .assignmentId,
      "a-001",
    );
    assert.equal(
      resolveAssignment({ monitored: true, link: null, pageAssignmentId: "unassigned", docKey })
        .assignmentId,
      null,
    );
  });

  test("navigating away from a linked document drops its assignment", () => {
    const session = { assignmentId: "a-002", linkedDocKey: docKey };
    assert.equal(
      resolveAssignment({
        monitored: true,
        link: null,
        pageAssignmentId: null,
        docKey: "https://docs.google.com/document/d/other",
        session,
      }).assignmentId,
      null,
    );
    // Same document, no new signal: keep it.
    assert.equal(
      resolveAssignment({ monitored: true, link: null, pageAssignmentId: null, docKey, session })
        .assignmentId,
      "a-002",
    );
  });
});

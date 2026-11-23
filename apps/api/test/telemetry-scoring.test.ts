import { readFileSync } from "node:fs";
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type { TelemetryEvent } from "../src/store/db";
import {
  computeEffortMetrics,
  computeEffortScore,
  computeIntegrityFlags,
} from "../src/services/effort";
// The extension's live popup score must agree with the server too.
import { applyEvents, computeScore, emptySession } from "../../extension/src/lib.js";

// Same file the Rust crate asserts in `scoring_matches_the_shared_parity_fixture`.
const FIXTURE = new URL(
  "../../../crates/telemetry-core/tests/fixtures/scoring-parity.json",
  import.meta.url,
);

interface FixtureEvent {
  type: unknown;
  payload: unknown;
}

interface FixtureCase {
  name: string;
  events: FixtureEvent[] | { repeat: number; type: string; payload: unknown };
  expected: {
    keystrokes: number;
    pastes: number;
    pasteVolume: number;
    aiTabSwitches: number;
    activeSeconds: number;
    score: number;
    flags: string[];
  };
}

const { cases } = JSON.parse(readFileSync(FIXTURE, "utf8")) as { cases: FixtureCase[] };

function expand(spec: FixtureCase["events"]): FixtureEvent[] {
  if (Array.isArray(spec)) {
    return spec;
  }
  return Array.from({ length: spec.repeat }, () => ({ type: spec.type, payload: spec.payload }));
}

function toEvents(raw: FixtureEvent[]): TelemetryEvent[] {
  return raw.map(
    (item, index) =>
      ({
        id: `e-${index}`,
        sessionId: "s-parity",
        assignmentId: "a-001",
        studentId: "u-student-1",
        type: item.type,
        occurredAt: "2026-10-19T10:00:00Z",
        payload: item.payload,
      }) as unknown as TelemetryEvent,
  );
}

describe("effort scoring parity fixture (shared with crates/telemetry-core)", () => {
  test("the fixture has cases", () => {
    assert.ok(cases.length >= 5);
  });

  for (const fixture of cases) {
    test(`API engine: ${fixture.name}`, () => {
      const metrics = computeEffortMetrics(toEvents(expand(fixture.events)));
      const { score, flags, ...expectedMetrics } = fixture.expected;
      assert.deepEqual(metrics, expectedMetrics);
      assert.equal(computeEffortScore(metrics), score);
      assert.deepEqual(computeIntegrityFlags(metrics), flags);
    });

    test(`extension popup score: ${fixture.name}`, () => {
      const raw = expand(fixture.events);
      const session = emptySession(1, "https://lms.example", 0, () => "s-parity");
      applyEvents(session, raw, 0);
      // The worker counts AI switches itself (tabs.onActivated), not in applyEvents.
      session.aiTabSwitches = raw.filter((event) => event.type === "ai_tab_switch").length;
      assert.equal(session.keystrokes, fixture.expected.keystrokes);
      assert.equal(session.pasteVolume, fixture.expected.pasteVolume);
      assert.equal(session.activeSeconds, fixture.expected.activeSeconds);
      assert.equal(computeScore(session), fixture.expected.score);
    });
  }
});

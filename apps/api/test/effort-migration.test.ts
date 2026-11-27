// Migration 4 namespaces effort_scores rows written before session ids were
// stored as `<studentId>:<sessionId>`, so later uploads for the same session
// update the pair's score instead of adding a row getEffortScore never reads.
// Runs on a real Postgres engine (PGlite) over a Unix socket.
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import pg from "pg";
import { MIGRATIONS, SCHEMA_MIGRATIONS_DDL } from "../src/store/migrations";
import { createPgStore, runMigrations } from "../src/store/pg-store";
import { effortRowKey } from "../src/routes/telemetry";

let socketDir: string;
let pglite: PGlite;
let server: PGLiteSocketServer;
let pool: pg.Pool;

const row = (sessionId: string, studentId: string, assignmentId: string, score: number) =>
  `('${sessionId}', '${assignmentId}', '${studentId}', ${score}, '2026-11-01T00:00:00.000Z')`;

before(async () => {
  socketDir = await mkdtemp(path.join(tmpdir(), "edtech-effort-mig-"));
  pglite = await PGlite.create();
  server = new PGLiteSocketServer({
    db: pglite,
    path: path.join(socketDir, ".s.PGSQL.5432"),
    maxConnections: 2,
  });
  await server.start();
  pool = new pg.Pool({ connectionString: `postgresql://postgres@/postgres?host=${socketDir}`, max: 1 });

  // A database deployed before migration 4, holding pre-namespacing rows.
  await pglite.exec(SCHEMA_MIGRATIONS_DDL);
  for (const migration of MIGRATIONS.filter((m) => m.version < 4)) {
    await pglite.exec(migration.sql);
    await pglite.exec(
      `INSERT INTO schema_migrations (version, name, applied_at)
       VALUES (${migration.version}, '${migration.name}', '2026-11-01T00:00:00.000Z')`,
    );
  }
  await pglite.exec(`
    INSERT INTO effort_scores (session_id, assignment_id, student_id, score, computed_at) VALUES
      ${row("sess-A", "stu-1", "a-1", 100)},
      ${row("sess-B", "stu-2", "a-1", 70)},
      ${row("stu-3:already", "stu-3", "a-1", 50)},
      ${row("sess-C", "stu-4", "a-1", 90)},
      ${row("stu-4:sess-C", "stu-4", "a-1", 40)};
  `);
});

after(async () => {
  await pool?.end();
  await server?.stop();
  await pglite?.close();
  await rm(socketDir, { recursive: true, force: true });
});

describe("migration 4: effort_scores_namespaced", () => {
  test("prefixes legacy rows and merges a legacy row with its namespaced twin", async () => {
    // Migration 4 and every later one are pending.
    assert.deepEqual(
      await runMigrations(pool),
      MIGRATIONS.filter((m) => m.version >= 4).map((m) => m.version),
    );
    const { rows } = await pool.query<{ session_id: string; score: number }>(
      "SELECT session_id, score FROM effort_scores ORDER BY seq",
    );
    assert.deepEqual(
      rows.map((entry) => [entry.session_id, entry.score]),
      [
        ["stu-1:sess-A", 100],
        ["stu-2:sess-B", 70],
        ["stu-3:already", 50],
        // The newer namespaced values win, at the legacy row's position.
        ["stu-4:sess-C", 40],
      ],
    );
    assert.deepEqual(await runMigrations(pool), [], "re-running is a no-op");
  });

  test("a new upload for a legacy session now updates the score the report reads", async () => {
    const store = createPgStore(pool);
    await store.setEffortScore({
      sessionId: effortRowKey("stu-1", "sess-A"),
      studentId: "stu-1",
      assignmentId: "a-1",
      score: 35,
      keystrokes: 10,
      pastes: 1,
      pasteVolume: 900,
      aiTabSwitches: 1,
      activeSeconds: 60,
      computedAt: "2026-11-23T00:00:00.000Z",
    });
    const score = await store.getEffortScore("stu-1", "a-1");
    assert.equal(score?.score, 35);
    const { rows } = await pool.query(
      "SELECT 1 FROM effort_scores WHERE student_id = 'stu-1' AND assignment_id = 'a-1'",
    );
    assert.equal(rows.length, 1, "no second row for the same session");
  });
});

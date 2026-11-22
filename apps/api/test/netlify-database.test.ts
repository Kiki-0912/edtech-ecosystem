// Netlify Database flow: Netlify applies the generated migration files at deploy
// with the owner role; functions connect with a role that may not change the
// schema. Runs on a real Postgres engine (PGlite) over a Unix socket.
import { readdir, readFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import pg from "pg";
import {
  MIGRATIONS,
  netlifyMigrationDir,
  netlifyMigrationSql,
} from "../src/store/migrations";
import { createPgStore, runMigrations, seedDatabase } from "../src/store/pg-store";
import { hashPassword, verifyPassword } from "../src/services/password";

const NETLIFY_MIGRATIONS = path.resolve(import.meta.dirname, "../netlify/database/migrations");

let socketDir: string;
let pglite: PGlite;
let server: PGLiteSocketServer;
let connectionString: string;

/** A pool whose sessions run as `role` (like a Netlify function's runtime role). */
function poolAs(role?: string): pg.Pool {
  const pool = new pg.Pool({ connectionString, max: 1 });
  if (role) pool.on("connect", (client) => void client.query(`SET ROLE ${role}`));
  return pool;
}

before(async () => {
  socketDir = await mkdtemp(path.join(tmpdir(), "edtech-netlify-db-"));
  pglite = await PGlite.create();
  server = new PGLiteSocketServer({
    db: pglite,
    path: path.join(socketDir, ".s.PGSQL.5432"),
    maxConnections: 4,
  });
  await server.start();
  connectionString = `postgresql://postgres@/postgres?host=${socketDir}`;

  // The runtime role: may read and write data but not create tables.
  await pglite.exec(`
    REVOKE CREATE ON SCHEMA public FROM PUBLIC;
    CREATE ROLE app_runtime NOLOGIN;
    GRANT USAGE ON SCHEMA public TO app_runtime;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_runtime;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_runtime;
  `);
});

after(async () => {
  await server?.stop();
  await pglite?.close();
  await rm(socketDir, { recursive: true, force: true });
});

describe("generated Netlify migration files", () => {
  test("match src/store/migrations.ts (run `npm run db:netlify-migrations`)", async () => {
    const dirs = (await readdir(NETLIFY_MIGRATIONS)).sort();
    assert.deepEqual(dirs, MIGRATIONS.map(netlifyMigrationDir).sort());
    for (const migration of MIGRATIONS) {
      const file = path.join(NETLIFY_MIGRATIONS, netlifyMigrationDir(migration), "migration.sql");
      assert.equal(await readFile(file, "utf8"), netlifyMigrationSql(migration), file);
    }
  });
});

describe("runtime role without schema privileges", () => {
  test("a pending migration fails with an actionable message", async () => {
    const pool = poolAs("app_runtime");
    try {
      await assert.rejects(runMigrations(pool), /cannot be applied.*db:netlify-migrations/s);
    } finally {
      await pool.end();
    }
  });

  test("after Netlify applies the files, the API skips DDL, seeds and serves data", async () => {
    // What Netlify does at deploy: apply each file once, with the owner role.
    // PGlite is one backend session, so drop the role a previous pool set.
    await pglite.exec("RESET ROLE");
    for (const migration of MIGRATIONS) {
      await pglite.exec(netlifyMigrationSql(migration));
    }

    const pool = poolAs("app_runtime");
    try {
      assert.deepEqual(await runMigrations(pool), []);
      const { seededDemo } = await seedDatabase(pool, {
        includeDemo: true,
        passwordHash: hashPassword("runtime-pass"),
        adminEmail: "admin@runtime.test",
      });
      assert.equal(seededDemo, true);

      const store = createPgStore(pool);
      const admin = await store.getUserAuthByEmail("admin@runtime.test");
      assert.ok(admin?.passwordHash && verifyPassword("runtime-pass", admin.passwordHash));
      assert.equal((await store.getDepartments("col-cttc")).length, 18);

      // Writes work through the runtime role (sequences included).
      const note = await store.upsertTeacherNote({
        courseId: "c-001",
        bookName: "Runtime",
        courseCode: "CIT-301",
        title: "Written by the runtime role",
        content: "",
        authorId: "u-teacher-1",
      });
      assert.equal(note.title, "Written by the runtime role");
    } finally {
      await pool.end();
    }
  });
});

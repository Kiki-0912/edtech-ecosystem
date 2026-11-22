// Write Netlify Database migration files from src/store/migrations.ts.
//   npm run db:netlify-migrations
// Netlify applies apps/api/netlify/database/migrations at deploy time with the
// database owner role; functions then only need to read and write data.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { MIGRATIONS, netlifyMigrationDir, netlifyMigrationSql } from "../store/migrations";

export const NETLIFY_MIGRATIONS_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../netlify/database/migrations",
);

for (const migration of MIGRATIONS) {
  const dir = path.join(NETLIFY_MIGRATIONS_ROOT, netlifyMigrationDir(migration));
  await mkdir(dir, { recursive: true });
  await writeFile(path.join(dir, "migration.sql"), netlifyMigrationSql(migration));
  console.log(`wrote ${path.relative(process.cwd(), path.join(dir, "migration.sql"))}`);
}

// Apply Postgres migrations and seed an empty database.
//   DATABASE_URL=postgres://... npm run db:migrate
// The API also does this on startup; this command is for deploy pipelines
// and for checking a connection string before pointing the API at it.
import { config } from "../config";
import { createPool, runMigrations, seedDatabase } from "../store/pg-store";

if (!config.databaseUrl) {
  console.error("DATABASE_URL is not set; nothing to migrate.");
  process.exit(1);
}

const pool = createPool(config.databaseUrl);
try {
  const applied = await runMigrations(pool);
  console.log(
    applied.length > 0
      ? `Applied migrations: ${applied.join(", ")}`
      : "Schema is up to date.",
  );
  const { seededDemo } = await seedDatabase(pool, { includeDemo: config.seedDemoData });
  console.log(
    seededDemo ? "Seeded demo accounts and courses." : "Reference data checked; no demo seed needed.",
  );
} catch (error) {
  console.error("Migration failed:", error);
  process.exitCode = 1;
} finally {
  await pool.end();
}

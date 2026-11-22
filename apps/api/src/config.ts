const parsedPort = Number.parseInt(process.env.PORT ?? "4000", 10);

export const config = {
  env: process.env.NODE_ENV ?? "development",
  // Dev fallback keeps local setup frictionless; set AUTH_SECRET in production.
  authSecret: process.env.AUTH_SECRET ?? "edtech-dev-secret-change-me",
  host: process.env.HOST ?? "0.0.0.0",
  port: Number.isFinite(parsedPort) ? parsedPort : 4000,
  corsOrigin: process.env.CORS_ORIGIN ?? "*",
  // Postgres connection string. Unset = seeded in-memory store (resets on restart).
  // NETLIFY_DATABASE_URL is set automatically by Netlify DB (Neon).
  databaseUrl:
    process.env.DATABASE_URL?.trim() || process.env.NETLIFY_DATABASE_URL?.trim() || null,
  // Seed demo accounts/courses into an empty database (shared demo password!).
  seedDemoData: (process.env.SEED_DEMO_DATA ?? "true").toLowerCase() !== "false",
  // Optional: password for every seeded account and email for the seeded admin,
  // so a public deployment doesn't use the documented demo password.
  seedDemoPassword: process.env.SEED_DEMO_PASSWORD || null,
  seedAdminEmail: process.env.SEED_ADMIN_EMAIL?.trim() || null,
};

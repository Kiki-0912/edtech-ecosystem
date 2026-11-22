const parsedPort = Number.parseInt(process.env.PORT ?? "4000", 10);

// Netlify Functions expose platform-injected variables (such as NETLIFY_DB_URL)
// through the `Netlify.env` global; elsewhere only `process.env` exists.
type EnvReader = { get(key: string): string | undefined };
const readEnv = (key: string): string | undefined => {
  const netlifyEnv = (globalThis as { Netlify?: { env?: EnvReader } }).Netlify?.env;
  return process.env[key] ?? netlifyEnv?.get(key) ?? undefined;
};

export const config = {
  env: process.env.NODE_ENV ?? "development",
  // Dev fallback keeps local setup frictionless; set AUTH_SECRET in production.
  authSecret: process.env.AUTH_SECRET ?? "edtech-dev-secret-change-me",
  host: process.env.HOST ?? "0.0.0.0",
  port: Number.isFinite(parsedPort) ? parsedPort : 4000,
  corsOrigin: process.env.CORS_ORIGIN ?? "*",
  // Postgres connection string. Unset = seeded in-memory store (resets on restart).
  // NETLIFY_DB_URL is injected into functions by Netlify Database. Read lazily:
  // platform variables may only be available once a function is invoked.
  get databaseUrl(): string | null {
    for (const key of ["DATABASE_URL", "NETLIFY_DB_URL", "NETLIFY_DATABASE_URL"]) {
      const value = readEnv(key)?.trim();
      if (value) return value;
    }
    return null;
  },
  // Seed demo accounts/courses into an empty database (shared demo password!).
  seedDemoData: (process.env.SEED_DEMO_DATA ?? "true").toLowerCase() !== "false",
  // Optional: password for every seeded account and email for the seeded admin,
  // so a public deployment doesn't use the documented demo password.
  seedDemoPassword: process.env.SEED_DEMO_PASSWORD || null,
  seedAdminEmail: process.env.SEED_ADMIN_EMAIL?.trim() || null,
};

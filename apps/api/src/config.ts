const parsedPort = Number.parseInt(process.env.PORT ?? "4000", 10);

// Netlify Functions expose platform-injected variables (such as NETLIFY_DB_URL)
// through the `Netlify.env` global; elsewhere only `process.env` exists.
type EnvReader = { get(key: string): string | undefined };
const readEnv = (key: string): string | undefined => {
  const netlifyEnv = (globalThis as { Netlify?: { env?: EnvReader } }).Netlify?.env;
  return process.env[key] ?? netlifyEnv?.get(key) ?? undefined;
};

/**
 * CORS_ORIGIN as @fastify/cors expects it: "*" (the default when unset), or
 * the list of allowed origins. A browser accepts one origin per response, so a
 * list is matched against the request's Origin instead of being sent as is.
 */
export function parseCorsOrigin(value: string | undefined): string | string[] {
  if (value === undefined) return "*";
  const origins = value
    .split(",")
    .map((origin) => origin.trim().replace(/\/+$/, ""))
    .filter(Boolean);
  return origins.includes("*") ? "*" : origins;
}

/** Local-only signing secret used when AUTH_SECRET is unset. Never valid in production. */
export const DEV_AUTH_SECRET = "edtech-dev-secret-change-me";

/**
 * Why this configuration must not serve traffic, or null if it is fine.
 * Production (NODE_ENV=production, or running as a Netlify Function) needs a
 * real AUTH_SECRET: with the public dev fallback anyone could mint tokens.
 */
export function unsafeConfigReason(input: {
  nodeEnv: string | undefined;
  authSecret: string | undefined;
  onNetlify: boolean;
}): string | null {
  const production = input.nodeEnv === "production" || input.onNetlify;
  if (!production) return null;
  const secret = input.authSecret?.trim();
  if (!secret || secret === DEV_AUTH_SECRET) {
    return "AUTH_SECRET must be set to a private value in production (it is unset or the dev fallback)";
  }
  return null;
}

/** Netlify Functions expose a `Netlify` global and inject NETLIFY_DB_URL. */
function runningOnNetlify(): boolean {
  return (
    (globalThis as { Netlify?: unknown }).Netlify !== undefined ||
    Boolean(readEnv("NETLIFY_DB_URL")?.trim())
  );
}

/** Throw (refusing to start) when the configuration is unsafe for production. */
export function assertSafeConfig(): void {
  const reason = unsafeConfigReason({
    nodeEnv: process.env.NODE_ENV,
    authSecret: readEnv("AUTH_SECRET"),
    onNetlify: runningOnNetlify(),
  });
  if (reason) throw new Error(`Refusing to start: ${reason}`);
}

export const config = {
  env: process.env.NODE_ENV ?? "development",
  // Dev fallback keeps local setup frictionless; production refuses to start
  // without a real AUTH_SECRET (see assertSafeConfig).
  get authSecret(): string {
    return readEnv("AUTH_SECRET")?.trim() || DEV_AUTH_SECRET;
  },
  host: process.env.HOST ?? "0.0.0.0",
  port: Number.isFinite(parsedPort) ? parsedPort : 4000,
  // "*" or a comma-separated list of origins, e.g. the web app and the separately
  // deployed admin console: "https://app.example.org,https://admin.example.org".
  get corsOrigin(): string | string[] {
    return parseCorsOrigin(process.env.CORS_ORIGIN);
  },
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
  // Return/log SMS sign-in codes (local demos only: anyone could sign in as any
  // phone). Off unless SMS_DEV_ECHO=true; `npm run dev:api` turns it on.
  get smsDevEcho(): boolean {
    return readEnv("SMS_DEV_ECHO") === "true";
  },
};

import { buildApp } from "./create-app";

// `npm run dev:api` passes this so local demos can sign in with SMS codes
// (a flag rather than an env var, so the script works in PowerShell too).
if (process.argv.includes("--sms-dev-echo")) {
  process.env.SMS_DEV_ECHO ??= "true";
}
import { config } from "./config";

const app = await buildApp();

// Close the HTTP server and the database pool cleanly on shutdown.
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    app.close().finally(() => process.exit(0));
  });
}

try {
  await app.listen({ host: config.host, port: config.port });
} catch (error) {
  app.log.error(error);
  process.exit(1);
}

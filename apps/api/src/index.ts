import { buildApp } from "./create-app";
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

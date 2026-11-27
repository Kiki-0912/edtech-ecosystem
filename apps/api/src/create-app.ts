import cors from "@fastify/cors";
import Fastify from "fastify";
import type { FastifyError } from "fastify";
import { authenticate } from "./middleware/auth";
import { assertSafeConfig, config } from "./config";
import { closeDb, initDb, pingDb, storeKind } from "./store/db";

interface ApiError {
  error: { code: string; message: string };
}
import { authRoutes } from "./routes/auth";
import { classroomRoutes } from "./routes/classroom";
import { courseRoutes } from "./routes/courses";
import { assignmentRoutes } from "./routes/assignments";
import { telemetryRoutes } from "./routes/telemetry";
import studentsRoutes from "./routes/students";
import departmentsRoutes from "./routes/departments";
import attendanceRoutes from "./routes/attendance";
import notesRoutes from "./routes/notes";
import excelRoutes from "./routes/excel";
import adminRoutes from "./routes/admin";

const PUBLIC_PREFIXES = [
  "/health",
  "/api/health",
  "/api/v1/auth",
];
const PUBLIC_PATHS = new Set(["/", "/api"]);

// Postgres constraint violations are client errors, not server faults.
const POSTGRES_CONSTRAINT_ERRORS: Record<
  string,
  { status: number; code: string; message: string } | undefined
> = {
  "23505": { status: 409, code: "CONFLICT", message: "A record with these values already exists" },
  "23503": { status: 400, code: "INVALID_REFERENCE", message: "A referenced record does not exist" },
  "23514": { status: 400, code: "INVALID_BODY", message: "A value is outside the allowed set" },
  "23502": { status: 400, code: "INVALID_BODY", message: "A required value is missing" },
};

export async function buildApp() {
  assertSafeConfig();
  await initDb();

  const app = Fastify({
    logger: {
      level: config.env === "production" ? "info" : "debug",
    },
    // Body schemas reject the wrong type (e.g. a number for a name) instead of
    // silently coercing it to a string.
    ajv: { customOptions: { coerceTypes: false } },
  });

  app.addHook("onClose", async () => {
    await closeDb();
  });

  await app.register(cors, { origin: config.corsOrigin });

  // Enforce bearer-token authentication on every route except public ones.
  app.addHook("preHandler", async (request, reply) => {
    // Fastify v5 renamed routerPath -> routeOptions.url.
    const url = request.routeOptions?.url ?? request.url;
    if (
      PUBLIC_PATHS.has(url) ||
      PUBLIC_PREFIXES.some((prefix) => url.startsWith(prefix))
    ) {
      return;
    }
    await authenticate(request, reply);
  });

  // Friendly landing responses for the service root and API base.
  const rootHandler = async () => ({
    status: "ok",
    service: "edtech-api",
    version: "0.1.0",
    health: "/health",
    api: "/api/v1",
  });
  app.get("/", rootHandler);
  app.get("/api", rootHandler);

  const healthHandler = async () => {
    const databaseOk = await pingDb();
    return {
      status: databaseOk ? "ok" : "degraded",
      service: "edtech-api",
      version: "0.1.0",
      storage: storeKind(),
      database: databaseOk ? "ok" : "unreachable",
      timestamp: new Date().toISOString(),
    };
  };
  app.get("/health", healthHandler);
  app.get("/api/health", healthHandler);

  // Must be set before the route plugins register: Fastify plugins capture
  // the error handler that exists when they are registered.
  app.setErrorHandler((error: FastifyError, request, reply) => {
    const constraint = POSTGRES_CONSTRAINT_ERRORS[error.code];
    if (constraint && !error.statusCode) {
      return reply.code(constraint.status).send({
        error: { code: constraint.code, message: constraint.message },
      } satisfies ApiError);
    }

    // Schema failures and unparseable JSON bodies are the client's fault.
    if (
      error.validation ||
      error.code === "FST_ERR_CTP_EMPTY_JSON_BODY" ||
      error.code === "FST_ERR_CTP_INVALID_JSON_BODY"
    ) {
      return reply.code(400).send({
        error: { code: "INVALID_BODY", message: error.message },
      } satisfies ApiError);
    }

    const statusCode = error.statusCode ?? 500;
    if (statusCode >= 500) {
      request.log.error(error);
    }

    const payload: ApiError = {
      error: {
        code: statusCode >= 500 ? "INTERNAL_ERROR" : "BAD_REQUEST",
        message:
          statusCode >= 500 ? "An unexpected error occurred" : error.message,
      },
    };
    return reply.code(statusCode).send(payload);
  });

  await app.register(courseRoutes, { prefix: "/api/v1" });
  await app.register(assignmentRoutes, { prefix: "/api/v1" });
  await app.register(telemetryRoutes, { prefix: "/api/v1" });
  await app.register(classroomRoutes, { prefix: "/api/v1" });
  await app.register(authRoutes, { prefix: "/api/v1/auth" });
  await app.register(studentsRoutes, { prefix: "/api/v1" });
  await app.register(departmentsRoutes, { prefix: "/api/v1" });
  await app.register(attendanceRoutes, { prefix: "/api/v1" });
  await app.register(notesRoutes, { prefix: "/api/v1" });
  await app.register(excelRoutes, { prefix: "/api/v1" });
  // Admin-only: the module's own preHandler rejects every other role.
  await app.register(adminRoutes, { prefix: "/api/v1/admin" });

  app.setNotFoundHandler((request, reply) => {
    const error: ApiError = {
      error: {
        code: "ROUTE_NOT_FOUND",
        message: `Route ${request.method} ${request.url} not found`,
      },
    };
    return reply.code(404).send(error);
  });

  return app;
}

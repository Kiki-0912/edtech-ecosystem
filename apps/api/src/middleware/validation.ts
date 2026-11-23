import type { FastifyReply, FastifyRequest } from "fastify";
import type { ApiError } from "../store/db";

/**
 * Route options that validate the JSON body against `schema` but defer the
 * verdict to the handler (`attachValidation`), so authentication and role
 * checks still answer 401/403 before a malformed body answers 400.
 * The handler must call `rejectInvalidBody` before reading the body.
 */
export function bodySchema(schema: Record<string, unknown>) {
  return { schema: { body: schema }, attachValidation: true } as const;
}

/** Sends 400 INVALID_BODY if the body failed its schema. Returns true if it replied. */
export function rejectInvalidBody(request: FastifyRequest, reply: FastifyReply): boolean {
  const error = request.validationError;
  if (!error) return false;
  reply.code(400).send({ error: { code: "INVALID_BODY", message: error.message } } satisfies ApiError);
  return true;
}

/** True if `value` parses as a date (ISO 8601 or anything Date.parse accepts). */
export function isDateString(value: unknown): value is string {
  return typeof value === "string" && value.trim() !== "" && !Number.isNaN(Date.parse(value));
}

/** A required, non-blank string. */
export const TEXT = { type: "string", minLength: 1, pattern: "\\S" } as const;
/** An optional string or null. */
export const NULLABLE_TEXT = { type: ["string", "null"] } as const;

import crypto from "node:crypto";
import type { FastifyInstance, FastifyReply } from "fastify";
import type {
  ApiError,
  EffortScore,
  IntegrityReport,
  SignedTelemetryBatch,
  TelemetryEvent,
} from "../store/db";
import {
  createTelemetryBatch,
  getAssignment,
  getCourse,
  getEffortScore,
  getIntegrityFlags,
  getSubmission,
  getSubmissionsByAssignment,
  getTelemetryBatch,
  getTelemetryBatchesFor,
  hasTelemetryBatch,
  getUser,
  setEffortScore,
  setIntegrityFlags,
  updateSubmission,
} from "../store/db";
import {
  buildEffortScore,
  computeEffortMetrics,
  computeIntegrityFlags,
} from "../services/effort";

const fail = (
  reply: FastifyReply,
  statusCode: number,
  code: string,
  message: string,
) => reply.code(statusCode).send({ error: { code, message } } satisfies ApiError);

/** effort_scores is keyed by session_id alone and the session id is chosen by
 *  the client, so rows are stored as `<studentId>:<sessionId>`: one student can
 *  never overwrite another's row by reusing their session id. */
export function effortRowKey(studentId: string, sessionId: string): string {
  return `${studentId}:${sessionId}`;
}

/** The client-facing session id of a stored score (legacy rows have no prefix). */
export function publicSessionId(studentId: string, stored: string): string {
  const prefix = `${studentId}:`;
  return stored.startsWith(prefix) ? stored.slice(prefix.length) : stored;
}

/** Every event of a student + assignment across stored batches, once per batchId. */
function eventsFor(
  batches: SignedTelemetryBatch[],
  studentId: string,
  assignmentId: string,
): TelemetryEvent[] {
  const seen = new Set<string>();
  const events: TelemetryEvent[] = [];
  for (const stored of batches) {
    if (
      stored.studentId !== studentId ||
      stored.assignmentId !== assignmentId ||
      seen.has(stored.batchId)
    ) {
      continue;
    }
    seen.add(stored.batchId);
    events.push(...stored.events);
  }
  return events;
}

/** Reconstruct the exact canonical JSON the extension signs over. Key order
 *  must match the client (batchId, studentId, assignmentId, createdAt, events). */
function canonicalBatch(batch: SignedTelemetryBatch): string {
  return JSON.stringify({
    batchId: batch.batchId,
    studentId: batch.studentId,
    assignmentId: batch.assignmentId,
    createdAt: batch.createdAt,
    events: batch.events,
  });
}

/** Verify an HMAC-SHA256 batch signature against the client's public JWK.
 *  The extension generates a single HMAC key per install and exports it as both
 *  "private" and "public" JWK (HMAC is symmetric). The clientPublicKey JWK
 *  carries the raw key material in its `k` field (base64url). */
function verifyBatchSignature(
  batch: SignedTelemetryBatch,
): { ok: boolean; reason?: string } {
  let publicKey: { kty?: string; k?: string };
  try {
    publicKey = JSON.parse(batch.clientPublicKey);
  } catch {
    return { ok: false, reason: "invalid-client-public-key" };
  }

  if (!publicKey.k || publicKey.kty !== "oct") {
    return { ok: false, reason: "invalid-hmac-jwk" };
  }

  let keyMaterial: Buffer;
  try {
    keyMaterial = Buffer.from(publicKey.k, "base64url");
  } catch {
    return { ok: false, reason: "invalid-key-material" };
  }

  const expected = crypto
    .createHmac("sha256", keyMaterial)
    .update(canonicalBatch(batch))
    .digest("base64url");

  const provided = Buffer.from(batch.clientSignature, "base64url");
  const wanted = Buffer.from(expected, "base64url");
  if (
    provided.length !== wanted.length ||
    !crypto.timingSafeEqual(provided, wanted)
  ) {
    return { ok: false, reason: "signature-mismatch" };
  }

  return { ok: true };
}

/**
 * Upload limits. The extension sends at most 1,000 events per batch (about
 * 230 KB); these leave headroom for older queued batches of up to 5,000 events
 * (about 1.2 MB, which Fastify's default 1 MiB body limit used to reject).
 * Anything bigger gets 413 so the extension splits it instead of dropping it.
 */
export const MAX_BATCH_EVENTS = 5_000;
export const TELEMETRY_BODY_LIMIT = 4 * 1024 * 1024;

export async function telemetryRoutes(app: FastifyInstance) {
  app.post<{ Body: SignedTelemetryBatch }>(
    "/telemetry/batches",
    { bodyLimit: TELEMETRY_BODY_LIMIT },
    async (request, reply) => {
      const batch = request.body;

      if (
        !batch ||
        typeof batch.batchId !== "string" ||
        typeof batch.studentId !== "string" ||
        typeof batch.assignmentId !== "string" ||
        typeof batch.clientSignature !== "string" ||
        typeof batch.clientPublicKey !== "string" ||
        !Array.isArray(batch.events) ||
        batch.events.length === 0
      ) {
        return fail(
          reply,
          400,
          "INVALID_BATCH",
          "A signed batch with at least one telemetry event is required",
        );
      }
      if (batch.events.length > MAX_BATCH_EVENTS) {
        return fail(
          reply,
          413,
          "BATCH_TOO_LARGE",
          `A batch can hold at most ${MAX_BATCH_EVENTS} events; split it and retry`,
        );
      }

      // The signature only proves the sender held the key it sent, so identity
      // comes from the bearer token: students upload only their own telemetry.
      const caller = (request as { user?: { id: string; role?: string } }).user;
      if (!caller || caller.id !== batch.studentId) {
        return fail(
          reply,
          403,
          "FORBIDDEN",
          "Telemetry can only be uploaded for your own account",
        );
      }

      // ---- Signature verification ----
      // 400, not 401: a bad signature is a malformed batch, and the extension
      // treats 401 as "sign in again", which would never fix it.
      const sigCheck = verifyBatchSignature(batch);
      if (!sigCheck.ok) {
        return fail(
          reply,
          400,
          "INVALID_SIGNATURE",
          `Telemetry batch signature invalid: ${sigCheck.reason}`,
        );
      }

      const assignment = await getAssignment(batch.assignmentId);
      if (!assignment) {
        return fail(reply, 404, "ASSIGNMENT_NOT_FOUND", "Assignment not found");
      }

      const student = await getUser(batch.studentId);
      if (!student || student.role !== "student") {
        return fail(reply, 404, "STUDENT_NOT_FOUND", "Student not found");
      }

      const inconsistent = batch.events.some(
        (event) =>
          !event ||
          typeof event.sessionId !== "string" ||
          event.assignmentId !== batch.assignmentId ||
          event.studentId !== batch.studentId,
      );
      if (inconsistent) {
        return fail(
          reply,
          400,
          "INCONSISTENT_EVENTS",
          "Every event must match the batch student and assignment",
        );
      }

      const sessionId = batch.events.at(-1)!.sessionId;
      const replayed = await getTelemetryBatch(batch.batchId);
      if (replayed && replayed.studentId !== batch.studentId) {
        return fail(reply, 409, "BATCH_CONFLICT", "This batch id is already in use");
      }

      if (!replayed) {
        await createTelemetryBatch(batch);
      }

      // Score from everything stored for this student + assignment (re-read
      // after the insert so concurrent uploads are included), never from the
      // latest batch alone. A replay changes nothing, so it writes nothing.
      const pairEvents = eventsFor(
        await getTelemetryBatchesFor(batch.studentId, batch.assignmentId),
        batch.studentId,
        batch.assignmentId,
      );
      const sessionScores = new Map<string, EffortScore>();
      const touched = replayed
        ? [sessionId]
        : [...new Set(batch.events.map((event) => event.sessionId))];
      for (const id of touched) {
        sessionScores.set(
          id,
          buildEffortScore(
            id,
            batch.studentId,
            batch.assignmentId,
            computeEffortMetrics(pairEvents.filter((event) => event.sessionId === id)),
          ),
        );
      }
      const score = sessionScores.get(sessionId)!;

      if (!replayed) {
        for (const [id, sessionScore] of sessionScores) {
          await setEffortScore({
            ...sessionScore,
            sessionId: effortRowKey(batch.studentId, id),
          });
        }
        await setIntegrityFlags(
          batch.studentId,
          batch.assignmentId,
          computeIntegrityFlags(computeEffortMetrics(pairEvents)),
        );

        const existing = await getSubmissionsByAssignment(batch.assignmentId);
        const submission = existing.find(
          (entry) => entry.studentId === batch.studentId,
        );
        if (submission) {
          await updateSubmission(submission.id, { effortScore: score.score });
        }
      }

      return reply.code(202).send({
        data: {
          batchId: batch.batchId,
          acceptedEvents: replayed ? 0 : batch.events.length,
          effortScore: score,
        },
      });
    },
  );

  app.get<{ Params: { assignmentId: string; studentId: string } }>(
    "/integrity/:assignmentId/:studentId",
    async (request, reply) => {
      const { assignmentId, studentId } = request.params;

      // Students see only their own report; teachers only for courses they
      // teach; admins see everything.
      const caller = (request as { user?: { id: string; role?: string } }).user;
      if (caller?.role === "student" && caller.id !== studentId) {
        return fail(reply, 403, "FORBIDDEN", "Students can only view their own report");
      }
      if (caller?.role === "teacher") {
        const assignment = await getAssignment(assignmentId);
        if (!assignment) {
          return fail(reply, 404, "ASSIGNMENT_NOT_FOUND", "Assignment not found");
        }
        const course = await getCourse(assignment.courseId);
        if (course?.teacherId !== caller.id) {
          return fail(reply, 403, "FORBIDDEN", "You do not teach this course");
        }
      } else if (caller?.role !== "student" && caller?.role !== "admin") {
        return fail(reply, 403, "FORBIDDEN", "Insufficient role for this route");
      }

      const score = await getEffortScore(studentId, assignmentId);

      if (!score) {
        return fail(
          reply,
          404,
          "REPORT_NOT_FOUND",
          "No telemetry has been recorded for this student and assignment",
        );
      }

      const submissions = await getSubmissionsByAssignment(assignmentId);
      const submission = submissions.find(
        (entry) => entry.studentId === studentId,
      );

      const report: IntegrityReport = {
        submissionId: submission?.id ?? null,
        assignmentId,
        studentId,
        effortScore: { ...score, sessionId: publicSessionId(studentId, score.sessionId) },
        flags: await getIntegrityFlags(studentId, assignmentId),
        replayAvailable: await hasTelemetryBatch(studentId, assignmentId),
        generatedAt: new Date().toISOString(),
      };

      return { data: report };
    },
  );
}

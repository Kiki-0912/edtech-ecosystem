import type { FastifyInstance, FastifyReply } from "fastify";
import type { ApiError } from "../store/db";
import { getSessionUser } from "../store/db";
import { SESSION_REVOKED_MESSAGE, verifyToken } from "../routes/auth";

const fail = (
  reply: FastifyReply,
  statusCode: number,
  code: string,
  message: string,
) => reply.code(statusCode).send({ error: { code, message } } satisfies ApiError);

/** Extract the Bearer token from the Authorization header. */
function extractToken(authHeader: string | undefined): string | null {
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return null;
  }
  return authHeader.substring(7);
}

/** Fastify preHandler: enforce a valid bearer token on every protected route.
 *  Sets `request.userId` so downstream handlers can scope data to the caller.
 *  Public routes (/health, /api/v1/auth/*) must register this hook themselves
 *  or skip it entirely. */
export async function authenticate(request: any, reply: FastifyReply) {
  const token = extractToken(request.headers.authorization);
  if (!token) {
    return fail(reply, 401, "UNAUTHORIZED", "Missing or invalid token");
  }

  const claims = verifyToken(token);
  if (!claims) {
    return fail(reply, 401, "UNAUTHORIZED", "Invalid or expired token");
  }

  const session = await getSessionUser(claims.userId);
  if (!session) {
    return fail(reply, 401, "UNAUTHORIZED", "User no longer exists");
  }
  const { user } = session;
  if (user.isActive === false) {
    return fail(reply, 401, "ACCOUNT_DISABLED", "This account has been disabled");
  }
  // A password reset, deactivation or role change bumps the version.
  if (session.tokenVersion !== claims.version) {
    return fail(reply, 401, "SESSION_REVOKED", SESSION_REVOKED_MESSAGE);
  }

  request.userId = user.id;
  request.user = { id: user.id, role: user.role };
}

/** Role guard: only allow the given roles. Must run after `authenticate`. */
export function requireRoles(...allowed: string[]) {
  return async (request: any, reply: FastifyReply) => {
    const userId = request.userId;
    const { getUser } = await import("../store/db");
    const user = await getUser(userId);
    if (!user || !allowed.includes(user.role)) {
      return fail(reply, 403, "FORBIDDEN", "Insufficient role for this route");
    }
  };
}

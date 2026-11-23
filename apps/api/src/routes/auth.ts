import crypto from "node:crypto";
import type { FastifyInstance, FastifyReply } from "fastify";
import type { ApiError, User } from "../store/db";
import {
  createUser,
  getSessionUser,
  getUserAuthByPhone,
  getUserAuthByEmail,
  getUserByPhone,
  getUsers,
  createSmsCode,
  verifySmsCode,
  markPhoneVerified,
} from "../store/db";
import { config } from "../config";
import { hashPassword, verifyPassword } from "../services/password";

const TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60; // 7 days

// SMS sign-in limits, per phone. With a 6-digit code this bounds an attacker
// to SMS_MAX_SENDS * SMS_MAX_ATTEMPTS guesses per SMS_SEND_WINDOW_MS.
const SMS_CODE_TTL_MS = 10 * 60 * 1000; // 10 min
const SMS_SEND_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const SMS_MAX_SENDS = 5;
const SMS_MAX_ATTEMPTS = 5;

const fail = (
  reply: FastifyReply,
  statusCode: number,
  code: string,
  message: string,
) => reply.code(statusCode).send({ error: { code, message } } satisfies ApiError);

export { hashPassword, verifyPassword } from "../services/password";

export const SESSION_REVOKED_MESSAGE = "This session has ended. Sign in again.";

/* ---------- signed bearer tokens (HMAC-SHA256) ---------- */

/**
 * `tokenVersion` is the user's current token version: bumping it in the store
 * (password reset, deactivation, role change) revokes every earlier token.
 */
export function generateToken(userId: string, tokenVersion: number): string {
  const issuedAt = Math.floor(Date.now() / 1000);
  const payload = {
    sub: userId,
    ver: tokenVersion,
    iat: issuedAt,
    exp: issuedAt + TOKEN_TTL_SECONDS,
  };
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = crypto
    .createHmac("sha256", config.authSecret)
    .update(body)
    .digest("base64url");
  return `${body}.${signature}`;
}

export interface TokenClaims {
  userId: string;
  /** Tokens from before token versions existed count as version 0. */
  version: number;
}

/** The claims of a validly signed, unexpired token, or null. */
export function verifyToken(token: string): TokenClaims | null {
  const separator = token.lastIndexOf(".");
  if (separator <= 0) {
    return null;
  }
  const body = token.slice(0, separator);
  const signature = token.slice(separator + 1);
  const expected = crypto
    .createHmac("sha256", config.authSecret)
    .update(body)
    .digest("base64url");

  const provided = Buffer.from(signature);
  const wanted = Buffer.from(expected);
  if (provided.length !== wanted.length || !crypto.timingSafeEqual(provided, wanted)) {
    return null;
  }

  try {
    const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf-8"));
    if (typeof payload.sub !== "string" || typeof payload.exp !== "number") {
      return null;
    }
    if (payload.exp < Math.floor(Date.now() / 1000)) {
      return null;
    }
    const version = payload.ver ?? 0;
    if (typeof version !== "number") {
      return null;
    }
    return { userId: payload.sub, version };
  } catch {
    return null;
  }
}

function generateSmsCode(): string {
  return crypto.randomInt(100000, 999999).toString();
}

export async function authRoutes(app: FastifyInstance) {
  // Register new user
  app.post<{
    Body: {
      phone?: string;
      email?: string;
      display_name?: string;
      password?: string;
      role?: string;
    };
  }>("/register", async (request, reply) => {
    const { phone, email, display_name, password, role } = request.body ?? {};

    if (!phone && !email) {
      return fail(reply, 400, "INVALID_BODY", "Phone or email is required");
    }

    if (!password || password.length < 6) {
      return fail(
        reply,
        400,
        "INVALID_BODY",
        "Password must be at least 6 characters",
      );
    }

    // Staff accounts are created by an admin (POST /api/v1/admin/users).
    if (role !== undefined && role !== "student") {
      return fail(
        reply,
        400,
        "INVALID_BODY",
        "Public sign-up creates student accounts; teachers are added by an admin",
      );
    }

    if (phone) {
      const existingByPhone = await getUserByPhone(phone);
      if (existingByPhone) {
        return fail(reply, 409, "USER_EXISTS", "User with this phone already exists");
      }
    }

    if (email) {
      const existingByEmail = (await getUsers()).find((u) => u.email === email);
      if (existingByEmail) {
        return fail(reply, 409, "USER_EXISTS", "User with this email already exists");
      }
    }

    const id = crypto.randomUUID();

    const user = await createUser({
      id,
      displayName: display_name || "New User",
      email: email || "",
      phone: phone || "",
      role: "student",
      courseIds: [],
      passwordHash: hashPassword(password),
      isPhoneVerified: 0,
    });

    const token = generateToken(user.id, 0);

    return reply.code(201).send({
      data: { user: publicUser(user), token },
    });
  });

  // Login with phone/email + password
  app.post<{
    Body: {
      phone?: string;
      email?: string;
      password?: string;
    };
  }>("/login", async (request, reply) => {
    const { phone, email, password } = request.body ?? {};

    if (!phone && !email) {
      return fail(reply, 400, "INVALID_BODY", "Phone or email is required");
    }

    if (!password) {
      return fail(reply, 400, "INVALID_BODY", "Password is required");
    }

    const credentials = phone
      ? await getUserAuthByPhone(phone)
      : await getUserAuthByEmail(email!);

    if (
      !credentials ||
      !credentials.passwordHash ||
      !verifyPassword(password, credentials.passwordHash)
    ) {
      return fail(reply, 401, "INVALID_CREDENTIALS", "Invalid phone/email or password");
    }

    const session = await getSessionUser(credentials.id);
    if (!session) {
      return fail(reply, 401, "INVALID_CREDENTIALS", "Invalid phone/email or password");
    }
    const { user } = session;
    if (user.isActive === false) {
      return fail(reply, 403, "ACCOUNT_DISABLED", "This account has been disabled");
    }

    const token = generateToken(user.id, session.tokenVersion);

    return {
      data: { user: publicUser(user), token },
    };
  });

  // Send SMS verification code
  app.post<{
    Body: { phone?: string };
  }>("/send-sms", async (request, reply) => {
    const { phone } = request.body ?? {};

    if (!phone) {
      return fail(reply, 400, "INVALID_BODY", "Phone is required");
    }

    const user = await getUserByPhone(phone);
    if (!user) {
      return fail(reply, 404, "USER_NOT_FOUND", "No account is registered for this phone");
    }
    if (user.role === "admin") {
      return smsRefusedForAdmin(reply);
    }

    const code = generateSmsCode();
    const now = Date.now();
    const issued = await createSmsCode(
      {
        id: crypto.randomUUID(),
        phone,
        code,
        expiresAt: new Date(now + SMS_CODE_TTL_MS).toISOString(),
      },
      {
        windowStart: new Date(now - SMS_SEND_WINDOW_MS).toISOString(),
        maxPerWindow: SMS_MAX_SENDS,
      },
    );
    if (issued === "rate_limited") {
      return fail(
        reply,
        429,
        "RATE_LIMITED",
        "Too many codes were requested for this phone. Try again later.",
      );
    }

    // A real SMS provider (Twilio/Vonage) would deliver this code. Returning or
    // logging it lets anyone sign in as that phone, so it happens only when a
    // local demo opts in explicitly (never by default, whatever NODE_ENV is).
    const echo = config.smsDevEcho;
    if (echo) {
      app.log.info({ phone }, `SMS verification code: ${code}`);
    }

    return {
      data: {
        message: "Verification code sent",
        phone,
        ...(echo ? { code } : {}),
      },
    };
  });

  // Verify SMS code
  app.post<{
    Body: { phone?: string; code?: string };
  }>("/verify-sms", async (request, reply) => {
    const { phone, code } = request.body ?? {};

    if (!phone || !code) {
      return fail(reply, 400, "INVALID_BODY", "Phone and code are required");
    }

    const found = await getUserByPhone(phone);
    if (found?.role === "admin") {
      return smsRefusedForAdmin(reply);
    }

    const valid = await verifySmsCode(phone, code, SMS_MAX_ATTEMPTS);
    if (!valid) {
      return fail(reply, 400, "INVALID_CODE", "Invalid or expired verification code");
    }

    const session = found && (await getSessionUser(found.id));
    if (!session) {
      return fail(reply, 404, "USER_NOT_FOUND", "User not found");
    }
    const { user } = session;
    if (user.isActive === false) {
      return fail(reply, 403, "ACCOUNT_DISABLED", "This account has been disabled");
    }
    // The role may have changed since the check above.
    if (user.role === "admin") {
      return smsRefusedForAdmin(reply);
    }

    await markPhoneVerified(phone);

    const token = generateToken(user.id, session.tokenVersion);

    return {
      data: { user: publicUser(user), token },
    };
  });

  // Get current user from token
  app.get<{ Headers: { authorization?: string } }>("/me", async (request, reply) => {
    const authHeader = request.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return fail(reply, 401, "UNAUTHORIZED", "Missing or invalid token");
    }

    const token = authHeader.substring(7);
    const claims = verifyToken(token);
    if (!claims) {
      return fail(reply, 401, "UNAUTHORIZED", "Invalid or expired token");
    }

    const session = await getSessionUser(claims.userId);
    if (!session) {
      return fail(reply, 404, "USER_NOT_FOUND", "User not found");
    }
    const { user } = session;
    // Same as authenticate(): a disabled account's tokens stop working, and so
    // does every token issued before the user's token version was bumped.
    if (user.isActive === false) {
      return fail(reply, 401, "ACCOUNT_DISABLED", "This account has been disabled");
    }
    if (session.tokenVersion !== claims.version) {
      return fail(reply, 401, "SESSION_REVOKED", SESSION_REVOKED_MESSAGE);
    }

    return { data: { user: publicUser(user) } };
  });
}

/** Admins sign in with their password only: SMS codes are easier to attack. */
function smsRefusedForAdmin(reply: FastifyReply) {
  return fail(
    reply,
    403,
    "SMS_SIGN_IN_DISABLED",
    "SMS sign-in is not available for admin accounts; sign in with your password",
  );
}

/** Strip server-only fields before returning a user to a client. */
function publicUser(user: User): Omit<User, "passwordHash"> {
  const { passwordHash: _ignored, ...safe } = user;
  return safe;
}

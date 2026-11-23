// Admin console API, registered under /api/v1/admin.
//
// The global preHandler in create-app.ts has already authenticated the caller
// (401 otherwise). The plugin-level hook below rejects every non-admin with 403
// before any route in this module runs, so a route added here cannot skip it.
import crypto from "node:crypto";
import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import type {
  AdminCourse,
  AdminCourseCreate,
  AdminUser,
  AdminUserCreate,
  AdminUserUpdate,
  IntegrityRow,
  Overview,
} from "@edtech/shared";
import type { ApiError, Course, Role, User } from "../store/db";
import {
  createCourse,
  createUser,
  deleteCourse,
  deleteUser,
  getAssignmentsByCourse,
  getCourse,
  getCourses,
  getEntityCounts,
  getIntegrityRows,
  getSchemaVersion,
  getUser,
  getUsers,
  pingDb,
  setCourseStudents,
  storeKind,
  updateCourse,
  updateUser,
} from "../store/db";
import { hashPassword } from "../services/password";

/** Same as the root and /health responses in create-app.ts. */
const API_VERSION = "0.1.0";
const ROLES: readonly Role[] = ["student", "teacher", "admin"];
const MIN_PASSWORD_LENGTH = 8;

type AuthedRequest = FastifyRequest & { user?: { id: string; role?: string } };
/** A JSON body as received: the contract's keys, values not yet validated. */
type Incoming<T> = { [K in keyof T]?: unknown };

const fail = (reply: FastifyReply, statusCode: number, code: string, message: string) =>
  reply.code(statusCode).send({ error: { code, message } } satisfies ApiError);

const isRole = (value: unknown): value is Role => ROLES.includes(value as Role);

/** A trimmed string, "" for absent, or null when the value is not a string. */
function optionalText(value: unknown): string | null {
  if (value === undefined) return "";
  return typeof value === "string" ? value.trim() : null;
}

/** A trimmed non-empty string, or null. */
function requiredText(value: unknown): string | null {
  const text = optionalText(value);
  return text ? text : null;
}

function toAdminUser(user: User): AdminUser {
  return {
    id: user.id,
    displayName: user.displayName,
    email: user.email,
    phone: user.phone,
    role: user.role,
    isActive: user.isActive !== false,
    isPhoneVerified: Boolean(user.isPhoneVerified),
    courseIds: user.courseIds,
    createdAt: user.createdAt,
  };
}

async function toAdminCourse(course: Course, users?: User[]): Promise<AdminCourse> {
  const teacher = users
    ? users.find((user) => user.id === course.teacherId)
    : await getUser(course.teacherId);
  return {
    id: course.id,
    title: course.title,
    code: course.code,
    term: course.term,
    teacherId: course.teacherId,
    teacherName: teacher?.displayName ?? "Unassigned",
    studentIds: course.studentIds,
    studentCount: course.studentIds.length,
    assignmentCount: (await getAssignmentsByCourse(course.id)).length,
    createdAt: course.createdAt,
  };
}

/** Which of the given non-empty email/phone another user already has. */
function findConflict(
  users: User[],
  email: string,
  phone: string,
  exceptId?: string,
): "email" | "phone" | null {
  for (const user of users) {
    if (user.id === exceptId) continue;
    if (email && user.email === email) return "email";
    if (phone && user.phone === phone) return "phone";
  }
  return null;
}

const lastAdmin = (reply: FastifyReply) =>
  fail(reply, 409, "LAST_ADMIN", "At least one active admin must remain");

const flagged = (row: IntegrityRow) => row.flags.some((flag) => flag !== "none");

const adminRoutes: FastifyPluginAsync = async (app) => {
  app.addHook("preHandler", async (request, reply) => {
    if ((request as AuthedRequest).user?.role !== "admin") {
      return fail(reply, 403, "FORBIDDEN", "Admin only");
    }
  });

  // ---------------- Users and roles ----------------

  app.get<{ Querystring: { role?: string; q?: string; status?: string } }>(
    "/users",
    async (request, reply) => {
      const role = request.query.role ?? "";
      const status = request.query.status || "all";
      const query = request.query.q ?? "";
      if (typeof query !== "string") {
        return fail(reply, 400, "INVALID_QUERY", "q must be a single value");
      }
      const q = query.trim().toLowerCase();
      if (role && !isRole(role)) {
        return fail(reply, 400, "INVALID_QUERY", "role must be student, teacher or admin");
      }
      if (!["active", "inactive", "all"].includes(status)) {
        return fail(reply, 400, "INVALID_QUERY", "status must be active, inactive or all");
      }

      const users = (await getUsers()).map(toAdminUser).filter((user) => {
        if (role && user.role !== role) return false;
        if (status !== "all" && user.isActive !== (status === "active")) return false;
        if (!q) return true;
        return [user.displayName, user.email, user.phone].some((field) =>
          field.toLowerCase().includes(q),
        );
      });
      return { data: users };
    },
  );

  app.post<{ Body: Incoming<AdminUserCreate> }>("/users", async (request, reply) => {
    const body = request.body ?? {};
    const displayName = requiredText(body.displayName);
    const email = optionalText(body.email);
    const phone = optionalText(body.phone);
    const { role, password } = body;

    if (!displayName) {
      return fail(reply, 400, "INVALID_BODY", "displayName is required");
    }
    if (email === null || phone === null || (!email && !phone)) {
      return fail(reply, 400, "INVALID_BODY", "Phone or email is required");
    }
    if (!isRole(role)) {
      return fail(reply, 400, "INVALID_BODY", "role must be student, teacher or admin");
    }
    if (typeof password !== "string" || password.length < MIN_PASSWORD_LENGTH) {
      return fail(
        reply,
        400,
        "INVALID_BODY",
        `Password must be at least ${MIN_PASSWORD_LENGTH} characters`,
      );
    }

    const conflict = findConflict(await getUsers(), email, phone);
    if (conflict) {
      return fail(reply, 409, "USER_EXISTS", `A user with this ${conflict} already exists`);
    }

    const user = await createUser({
      id: crypto.randomUUID(),
      displayName,
      email,
      phone,
      role,
      courseIds: [],
      passwordHash: hashPassword(password),
      isPhoneVerified: 0,
    });
    return reply.code(201).send({ data: toAdminUser(user) });
  });

  app.patch<{ Params: { id: string }; Body: Incoming<AdminUserUpdate> }>(
    "/users/:id",
    async (request, reply) => {
      const callerId = (request as AuthedRequest).user?.id;
      const users = await getUsers();
      const user = users.find((entry) => entry.id === request.params.id);
      if (!user) {
        return fail(reply, 404, "USER_NOT_FOUND", "User not found");
      }

      const body = request.body ?? {};
      const displayName = body.displayName === undefined ? undefined : requiredText(body.displayName);
      const email = body.email === undefined ? undefined : optionalText(body.email);
      const phone = body.phone === undefined ? undefined : optionalText(body.phone);
      const { role, isActive } = body;

      if (displayName === null) {
        return fail(reply, 400, "INVALID_BODY", "displayName cannot be empty");
      }
      if (email === null || phone === null) {
        return fail(reply, 400, "INVALID_BODY", "email and phone must be strings");
      }
      if (role !== undefined && !isRole(role)) {
        return fail(reply, 400, "INVALID_BODY", "role must be student, teacher or admin");
      }
      if (isActive !== undefined && typeof isActive !== "boolean") {
        return fail(reply, 400, "INVALID_BODY", "isActive must be true or false");
      }
      const nextEmail = email ?? user.email;
      const nextPhone = phone ?? user.phone;
      if (!nextEmail && !nextPhone) {
        return fail(reply, 400, "INVALID_BODY", "Phone or email is required");
      }

      const roleChanged = role !== undefined && role !== user.role;
      const deactivating = isActive === false && user.isActive !== false;
      // Checked before LAST_ADMIN: the caller is always an active admin, so
      // when they are the only one this is still about changing themself.
      if ((roleChanged || deactivating) && user.id === callerId) {
        return fail(
          reply,
          409,
          "CANNOT_MODIFY_SELF",
          "You cannot change your own role or disable your own account",
        );
      }
      if (
        roleChanged &&
        user.role === "teacher" &&
        (await getCourses()).some((course) => course.teacherId === user.id)
      ) {
        return fail(
          reply,
          409,
          "USER_IN_USE",
          "This teacher is assigned to a course; reassign the course first",
        );
      }
      const conflict = findConflict(
        users,
        email === undefined ? "" : nextEmail,
        phone === undefined ? "" : nextPhone,
        user.id,
      );
      if (conflict) {
        return fail(reply, 409, "USER_EXISTS", `A user with this ${conflict} already exists`);
      }

      // Only students are on course rosters. Leave them while still a student,
      // so their courseIds follow (the store only prunes students' courseIds).
      if (roleChanged && user.role === "student") {
        for (const course of await getCourses()) {
          if (course.studentIds.includes(user.id)) {
            await setCourseStudents(
              course.id,
              course.studentIds.filter((id) => id !== user.id),
            );
          }
        }
      }
      // The store refuses to remove the last active admin in the same step as
      // the write, so concurrent requests cannot both pass the check.
      const result = await updateUser(user.id, {
        displayName,
        email,
        phone,
        role: roleChanged ? role : undefined,
        isActive,
      });
      if (result === "last_admin") return lastAdmin(reply);
      const updated = await getUser(user.id);
      if (result === "not_found" || !updated) {
        return fail(reply, 404, "USER_NOT_FOUND", "User not found");
      }
      return { data: toAdminUser(updated) };
    },
  );

  app.post<{ Params: { id: string }; Body: { password?: unknown } }>(
    "/users/:id/password",
    async (request, reply) => {
      const password = request.body?.password;
      if (typeof password !== "string" || password.length < MIN_PASSWORD_LENGTH) {
        return fail(
          reply,
          400,
          "INVALID_BODY",
          `Password must be at least ${MIN_PASSWORD_LENGTH} characters`,
        );
      }
      // Also revokes the user's existing tokens (see updateUser).
      const result = await updateUser(request.params.id, { passwordHash: hashPassword(password) });
      if (result === "not_found") {
        return fail(reply, 404, "USER_NOT_FOUND", "User not found");
      }
      return { data: { success: true } };
    },
  );

  app.delete<{ Params: { id: string } }>("/users/:id", async (request, reply) => {
    const callerId = (request as AuthedRequest).user?.id;
    const user = await getUser(request.params.id);
    if (!user) {
      return fail(reply, 404, "USER_NOT_FOUND", "User not found");
    }
    if (user.id === callerId) {
      return fail(reply, 409, "CANNOT_MODIFY_SELF", "You cannot delete your own account");
    }

    // LAST_ADMIN is decided inside the store's delete, like updateUser.
    const result = await deleteUser(user.id);
    if (result === "not_found") {
      return fail(reply, 404, "USER_NOT_FOUND", "User not found");
    }
    if (result === "last_admin") return lastAdmin(reply);
    if (result === "in_use") {
      return fail(
        reply,
        409,
        "USER_IN_USE",
        "This user teaches a course or wrote course notes; reassign them or disable the account",
      );
    }
    return { data: { success: true } };
  });

  // ---------------- Courses and enrollment ----------------

  /** 400 unless `teacherId` is an existing teacher. Returns false if it replied. */
  const checkTeacher = async (reply: FastifyReply, teacherId: string) => {
    const teacher = await getUser(teacherId);
    if (teacher?.role === "teacher") return true;
    fail(reply, 400, "INVALID_TEACHER", "teacherId must be an existing teacher");
    return false;
  };

  app.get("/courses", async () => {
    const users = await getUsers();
    const courses = await getCourses();
    return { data: await Promise.all(courses.map((course) => toAdminCourse(course, users))) };
  });

  app.post<{ Body: Incoming<AdminCourseCreate> }>("/courses", async (request, reply) => {
    const body = request.body ?? {};
    const title = requiredText(body.title);
    const code = requiredText(body.code);
    const term = requiredText(body.term);
    const teacherId = requiredText(body.teacherId);
    if (!title || !code || !term || !teacherId) {
      return fail(reply, 400, "INVALID_BODY", "title, code, term and teacherId are required");
    }
    if (!(await checkTeacher(reply, teacherId))) return reply;

    const course = await createCourse({ title, code, term, teacherId });
    return reply.code(201).send({ data: await toAdminCourse(course) });
  });

  app.patch<{ Params: { id: string }; Body: Incoming<AdminCourseCreate> }>(
    "/courses/:id",
    async (request, reply) => {
      if (!(await getCourse(request.params.id))) {
        return fail(reply, 404, "COURSE_NOT_FOUND", "Course not found");
      }
      const body = request.body ?? {};
      const updates: Partial<AdminCourseCreate> = {};
      for (const field of ["title", "code", "term", "teacherId"] as const) {
        if (body[field] === undefined) continue;
        const value = requiredText(body[field]);
        if (!value) {
          return fail(reply, 400, "INVALID_BODY", `${field} cannot be empty`);
        }
        updates[field] = value;
      }
      if (updates.teacherId !== undefined && !(await checkTeacher(reply, updates.teacherId))) {
        return reply;
      }

      const course = await updateCourse(request.params.id, updates);
      if (!course) {
        return fail(reply, 404, "COURSE_NOT_FOUND", "Course not found");
      }
      return { data: await toAdminCourse(course) };
    },
  );

  app.delete<{ Params: { id: string } }>("/courses/:id", async (request, reply) => {
    if (!(await deleteCourse(request.params.id))) {
      return fail(reply, 404, "COURSE_NOT_FOUND", "Course not found");
    }
    return { data: { success: true } };
  });

  app.put<{ Params: { id: string }; Body: { studentIds?: unknown } }>(
    "/courses/:id/students",
    async (request, reply) => {
      if (!(await getCourse(request.params.id))) {
        return fail(reply, 404, "COURSE_NOT_FOUND", "Course not found");
      }
      const studentIds = request.body?.studentIds;
      if (!Array.isArray(studentIds) || !studentIds.every((id) => typeof id === "string")) {
        return fail(reply, 400, "INVALID_BODY", "studentIds must be an array of user ids");
      }

      const students = new Set(
        (await getUsers()).filter((user) => user.role === "student").map((user) => user.id),
      );
      const invalid = [...new Set(studentIds)].filter((id) => !students.has(id));
      if (invalid.length > 0) {
        return fail(reply, 400, "INVALID_STUDENT", `Not students: ${invalid.join(", ")}`);
      }

      const course = await setCourseStudents(request.params.id, studentIds);
      if (!course) {
        return fail(reply, 404, "COURSE_NOT_FOUND", "Course not found");
      }
      return { data: await toAdminCourse(course) };
    },
  );

  // ---------------- Integrity and system ----------------

  app.get<{ Querystring: { flagged?: string } }>("/integrity", async (request, reply) => {
    const filter = request.query.flagged || "false";
    if (filter !== "true" && filter !== "false") {
      return fail(reply, 400, "INVALID_QUERY", "flagged must be true or false");
    }
    const rows = (await getIntegrityRows())
      .filter((row) => filter === "false" || flagged(row))
      .sort(
        (a, b) =>
          b.computedAt.localeCompare(a.computedAt) ||
          a.studentId.localeCompare(b.studentId) ||
          a.assignmentId.localeCompare(b.assignmentId),
      );
    return { data: rows };
  });

  app.get("/overview", async () => {
    const [counts, rows, databaseOk, schemaVersion] = await Promise.all([
      getEntityCounts(),
      getIntegrityRows(),
      pingDb(),
      getSchemaVersion(),
    ]);
    const overview: Overview = {
      counts: { ...counts, flaggedReports: rows.filter(flagged).length },
      storage: storeKind(),
      database: databaseOk ? "ok" : "unreachable",
      schemaVersion,
      version: API_VERSION,
      serverTime: new Date().toISOString(),
    };
    return { data: overview };
  });
};

export default adminRoutes;

// Teachers (of the course) and admins create, edit and delete assignments.
// Reads and submissions live in courses.ts. The store keeps each assignment's
// deadline calendar event in sync (none while it is a draft).
import type { FastifyInstance, FastifyReply } from "fastify";
import type { AssignmentCreate, AssignmentUpdate } from "@edtech/shared";
import type { ApiError } from "../store/db";
import {
  createAssignment,
  deleteAssignment,
  getAssignment,
  getCourse,
  updateAssignment,
} from "../store/db";
import { callerOf, managesCourse } from "../middleware/scope";
import { TEXT, bodySchema, isDateString, rejectInvalidBody } from "../middleware/validation";

const ASSIGNMENT_PROPERTIES = {
  title: { ...TEXT, maxLength: 200 },
  brief: { type: "string", maxLength: 10_000 },
  dueAt: TEXT,
  status: { type: "string", enum: ["draft", "open", "closed"] },
};
const CREATE_ASSIGNMENT_SCHEMA = {
  type: "object",
  required: ["title", "dueAt"],
  properties: ASSIGNMENT_PROPERTIES,
};
const UPDATE_ASSIGNMENT_SCHEMA = {
  type: "object",
  properties: ASSIGNMENT_PROPERTIES,
  // At least one known field.
  anyOf: Object.keys(ASSIGNMENT_PROPERTIES).map((key) => ({ required: [key] })),
};

const fail = (
  reply: FastifyReply,
  statusCode: number,
  code: string,
  message: string,
) => reply.code(statusCode).send({ error: { code, message } } satisfies ApiError);

export async function assignmentRoutes(app: FastifyInstance) {
  app.post<{ Params: { courseId: string }; Body: AssignmentCreate }>(
    "/courses/:courseId/assignments",
    bodySchema(CREATE_ASSIGNMENT_SCHEMA),
    async (request, reply) => {
      const caller = callerOf(request);
      if (caller?.role !== "admin" && caller?.role !== "teacher") {
        return fail(reply, 403, "FORBIDDEN", "Only teachers and admins can create assignments");
      }
      const course = await getCourse(request.params.courseId);
      if (!course) {
        return fail(reply, 404, "COURSE_NOT_FOUND", "Course not found");
      }
      if (!managesCourse(caller, course)) {
        return fail(reply, 403, "FORBIDDEN", "You can only add assignments to courses you teach");
      }
      if (rejectInvalidBody(request, reply)) return reply;

      const { title, brief, dueAt, status } = request.body;
      if (!isDateString(dueAt)) {
        return fail(reply, 400, "INVALID_BODY", "dueAt must be a date");
      }
      const assignment = await createAssignment(course.id, {
        title: title.trim(),
        brief: brief ?? "",
        dueAt,
        status: status ?? "open",
      });
      return reply.code(201).send({ data: assignment });
    },
  );

  app.patch<{ Params: { assignmentId: string }; Body: AssignmentUpdate }>(
    "/assignments/:assignmentId",
    bodySchema(UPDATE_ASSIGNMENT_SCHEMA),
    async (request, reply) => {
      const caller = callerOf(request);
      if (caller?.role !== "admin" && caller?.role !== "teacher") {
        return fail(reply, 403, "FORBIDDEN", "Only teachers and admins can edit assignments");
      }
      const existing = await getAssignment(request.params.assignmentId);
      if (!existing) {
        return fail(reply, 404, "ASSIGNMENT_NOT_FOUND", "Assignment not found");
      }
      if (!managesCourse(caller, await getCourse(existing.courseId))) {
        return fail(reply, 403, "FORBIDDEN", "You can only edit assignments of courses you teach");
      }
      if (rejectInvalidBody(request, reply)) return reply;

      const { title, brief, dueAt, status } = request.body;
      if (dueAt !== undefined && !isDateString(dueAt)) {
        return fail(reply, 400, "INVALID_BODY", "dueAt must be a date");
      }
      const assignment = await updateAssignment(existing.id, {
        title: title?.trim(),
        brief,
        dueAt,
        status,
      });
      if (!assignment) {
        return fail(reply, 404, "ASSIGNMENT_NOT_FOUND", "Assignment not found");
      }
      return { data: assignment };
    },
  );

  app.delete<{ Params: { assignmentId: string } }>(
    "/assignments/:assignmentId",
    async (request, reply) => {
      const caller = callerOf(request);
      if (caller?.role !== "admin" && caller?.role !== "teacher") {
        return fail(reply, 403, "FORBIDDEN", "Only teachers and admins can delete assignments");
      }
      const existing = await getAssignment(request.params.assignmentId);
      if (!existing) {
        return fail(reply, 404, "ASSIGNMENT_NOT_FOUND", "Assignment not found");
      }
      if (!managesCourse(caller, await getCourse(existing.courseId))) {
        return fail(
          reply,
          403,
          "FORBIDDEN",
          "You can only delete assignments of courses you teach",
        );
      }
      if (!(await deleteAssignment(existing.id))) {
        return fail(reply, 404, "ASSIGNMENT_NOT_FOUND", "Assignment not found");
      }
      return { data: { success: true } };
    },
  );
}

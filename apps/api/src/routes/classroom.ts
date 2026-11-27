import type { FastifyInstance, FastifyReply } from "fastify";
import type { ApiError, ChatMessage } from "../store/db";
import {
  createCalendarEvent,
  createMessage,
  deleteCalendarEvent,
  getCalendarEvent,
  getCalendarEvents,
  getChannel,
  getChannelsByCourse,
  getCourse,
  getCourses,
  getMessages,
  getUser,
  getUsers,
  updateCalendarEvent,
} from "../store/db";
import type { CalendarEventKind } from "../store/db";
import { callerOf, managesCourseId, readableCourseIds } from "../middleware/scope";
import {
  NULLABLE_TEXT,
  TEXT,
  bodySchema,
  isDateString,
  rejectInvalidBody,
} from "../middleware/validation";

const EVENT_KINDS: CalendarEventKind[] = ["assignment", "quiz", "class", "institution"];

const EVENT_PROPERTIES = {
  title: TEXT,
  kind: { type: "string", enum: EVENT_KINDS },
  startsAt: TEXT,
  endsAt: NULLABLE_TEXT,
  departmentId: NULLABLE_TEXT,
  courseId: NULLABLE_TEXT,
};
const CREATE_EVENT_SCHEMA = {
  type: "object",
  required: ["title", "kind", "startsAt"],
  properties: EVENT_PROPERTIES,
};
const UPDATE_EVENT_SCHEMA = { type: "object", properties: EVENT_PROPERTIES };

/** startsAt/endsAt must parse as dates when present. Returns an error message or null. */
function invalidEventDates(body: { startsAt?: string; endsAt?: string | null }): string | null {
  if (body.startsAt !== undefined && !isDateString(body.startsAt)) {
    return "startsAt must be a date";
  }
  if (body.endsAt !== undefined && body.endsAt !== null && !isDateString(body.endsAt)) {
    return "endsAt must be a date or null";
  }
  return null;
}

const ASSIGNMENT_EVENT_MESSAGE =
  "This deadline comes from an assignment; edit the assignment instead";

const fail = (
  reply: FastifyReply,
  statusCode: number,
  code: string,
  message: string,
) => reply.code(statusCode).send({ error: { code, message } } satisfies ApiError);

export async function classroomRoutes(app: FastifyInstance) {
  app.get<{
    Querystring: { userId?: string; departmentId?: string };
  }>("/calendar", async (request, reply) => {
    const caller = callerOf(request);
    const departmentId = request.query.departmentId;
    let courseIds: Set<string>;

    // Only admins may look at another user's calendar; everyone else always
    // gets their own, whatever userId they pass.
    if (caller?.role !== "admin") {
      courseIds = await readableCourseIds(caller);
      const events = await getCalendarEvents(courseIds, departmentId);
      return {
        data: events.filter((event) => event.courseId === null || courseIds.has(event.courseId)),
      };
    }

    const userId = request.query.userId;
    if (userId) {
      const user = await getUser(userId);
      if (!user) {
        return fail(reply, 404, "USER_NOT_FOUND", "User not found");
      }

      if (user.role === "admin") {
        courseIds = new Set((await getCourses()).map((course) => course.id));
      } else if (user.role === "teacher") {
        courseIds = new Set(
          (await getCourses())
            .filter((course) => course.teacherId === user.id)
            .map((course) => course.id),
        );
      } else {
        courseIds = new Set(user.courseIds);
      }
    } else {
      courseIds = new Set((await getCourses()).map((course) => course.id));
    }

    return { data: await getCalendarEvents(courseIds, departmentId) };
  });

  app.post<{
    Body: {
      title?: string;
      kind?: CalendarEventKind;
      startsAt?: string;
      endsAt?: string | null;
      departmentId?: string | null;
      courseId?: string | null;
    };
  }>("/calendar", bodySchema(CREATE_EVENT_SCHEMA), async (request, reply) => {
    const caller = callerOf(request);
    if (caller?.role !== "admin" && caller?.role !== "teacher") {
      return fail(reply, 403, "FORBIDDEN", "Admin or teacher only");
    }
    if (rejectInvalidBody(request, reply)) return reply;

    const { title, kind, startsAt, endsAt, departmentId, courseId } =
      request.body ?? {};
    if (!title || !kind || !startsAt) {
      return fail(
        reply,
        400,
        "INVALID_BODY",
        "title, kind and startsAt are required",
      );
    }
    const dateError = invalidEventDates({ startsAt, endsAt });
    if (dateError) return fail(reply, 400, "INVALID_BODY", dateError);
    // Course-less (institution-wide) events are admin-only, like editing them:
    // a teacher picks one of their courses, so they can manage it afterwards.
    if (!(await managesCourseId(caller, courseId))) {
      return fail(reply, 403, "FORBIDDEN", "You can only add events to courses you teach");
    }

    const event = await createCalendarEvent({
      title,
      kind,
      startsAt,
      endsAt: endsAt ?? null,
      departmentId: departmentId ?? null,
      courseId: courseId ?? null,
    });
    return reply.code(201).send({ data: event });
  });

  app.put<{
    Params: { eventId: string };
    Body: {
      title?: string;
      kind?: CalendarEventKind;
      startsAt?: string;
      endsAt?: string | null;
      departmentId?: string | null;
      courseId?: string | null;
    };
  }>("/calendar/:eventId", bodySchema(UPDATE_EVENT_SCHEMA), async (request, reply) => {
    const caller = callerOf(request);
    if (caller?.role !== "admin" && caller?.role !== "teacher") {
      return fail(reply, 403, "FORBIDDEN", "Admin or teacher only");
    }
    if (rejectInvalidBody(request, reply)) return reply;
    const body = request.body ?? {};
    const dateError = invalidEventDates(body);
    if (dateError) return fail(reply, 400, "INVALID_BODY", dateError);

    const existing = await getCalendarEvent(request.params.eventId);
    if (!existing) {
      return fail(reply, 404, "EVENT_NOT_FOUND", "Calendar event not found");
    }
    // A teacher may edit only their own courses' events, and not move one
    // into a course they do not teach.
    if (
      !(await managesCourseId(caller, existing.courseId)) ||
      (body.courseId !== undefined && !(await managesCourseId(caller, body.courseId)))
    ) {
      return fail(reply, 403, "FORBIDDEN", "You can only edit events of courses you teach");
    }
    if (existing.assignmentId) {
      return fail(reply, 409, "ASSIGNMENT_EVENT", ASSIGNMENT_EVENT_MESSAGE);
    }

    const event = await updateCalendarEvent(request.params.eventId, body);
    if (!event) {
      return fail(reply, 404, "EVENT_NOT_FOUND", "Calendar event not found");
    }
    return { data: event };
  });

  app.delete<{ Params: { eventId: string } }>(
    "/calendar/:eventId",
    async (request, reply) => {
      const caller = callerOf(request);
      if (caller?.role !== "admin" && caller?.role !== "teacher") {
        return fail(reply, 403, "FORBIDDEN", "Admin or teacher only");
      }

      const existing = await getCalendarEvent(request.params.eventId);
      if (!existing) {
        return fail(reply, 404, "EVENT_NOT_FOUND", "Calendar event not found");
      }
      if (!(await managesCourseId(caller, existing.courseId))) {
        return fail(reply, 403, "FORBIDDEN", "You can only delete events of courses you teach");
      }
      if (existing.assignmentId) {
        return fail(reply, 409, "ASSIGNMENT_EVENT", ASSIGNMENT_EVENT_MESSAGE);
      }

      if (!(await deleteCalendarEvent(request.params.eventId))) {
        return fail(reply, 404, "EVENT_NOT_FOUND", "Calendar event not found");
      }
      return { data: { success: true } };
    },
  );

  app.get<{ Params: { courseId: string } }>(
    "/courses/:courseId/channels",
    async (request, reply) => {
      const course = await getCourse(request.params.courseId);
      if (!course) {
        return fail(reply, 404, "COURSE_NOT_FOUND", "Course not found");
      }

      return {
        data: await getChannelsByCourse(course.id),
      };
    },
  );

  app.get<{ Params: { channelId: string } }>(
    "/channels/:channelId/messages",
    async (request, reply) => {
      const channel = await getChannel(request.params.channelId);
      if (!channel) {
        return fail(reply, 404, "CHANNEL_NOT_FOUND", "Channel not found");
      }
      // Reading is members-only, like posting.
      const callerId = callerOf(request)?.id;
      if (!callerId || !channel.memberIds.includes(callerId)) {
        return fail(reply, 403, "NOT_A_MEMBER", "User is not a member of this channel");
      }

      const data = await getMessages(channel.id);
      data.sort((a, b) => a.sentAt.localeCompare(b.sentAt));

      return { data };
    },
  );

  app.post<{
    Params: { channelId: string };
    Body: { authorId?: string; body?: string };
  }>("/channels/:channelId/messages", async (request, reply) => {
    const channel = await getChannel(request.params.channelId);
    if (!channel) {
      return fail(reply, 404, "CHANNEL_NOT_FOUND", "Channel not found");
    }

    // The author is always the signed-in caller; a body-supplied authorId
    // could otherwise be used to post as someone else.
    const authorId = (request as { userId?: string }).userId;
    const body = request.body?.body?.trim();

    if (!authorId || !body) {
      return fail(reply, 400, "INVALID_BODY", "body is required");
    }

    if (!channel.memberIds.includes(authorId)) {
      return fail(reply, 403, "NOT_A_MEMBER", "User is not a member of this channel");
    }

    if (channel.kind === "announcement") {
      const author = await getUser(authorId);
      if (author?.role === "student") {
        return fail(
          reply,
          403,
          "ANNOUNCEMENT_RESTRICTED",
          "Students cannot post in announcement channels",
        );
      }
    }

    const message = await createMessage({
      channelId: channel.id,
      authorId,
      body,
    });
    return reply.code(201).send({ data: message });
  });
}

import type { FastifyInstance, FastifyReply } from "fastify";
import type { ApiError, Assignment, Attachment, Course, Submission, User } from "../store/db";
import {
  createSubmission,
  getAssignment,
  getAssignmentsByCourse,
  getColleges,
  getCourse,
  getCourses,
  getDepartments,
  getSubmission,
  getSubmissionsByAssignment,
  getUser,
  getUsers,
  updateSubmission,
} from "../store/db";
import type { Caller } from "../middleware/scope";
import { callerOf, managesCourse } from "../middleware/scope";

/** Drafts are visible only to those who manage the course (its teacher, admins). */
async function visibleAssignments(
  caller: Caller | undefined,
  course: Course,
): Promise<Assignment[]> {
  const all = await getAssignmentsByCourse(course.id);
  return managesCourse(caller, course) ? all : all.filter((a) => a.status !== "draft");
}

const fail = (
  reply: FastifyReply,
  statusCode: number,
  code: string,
  message: string,
) => reply.code(statusCode).send({ error: { code, message } } satisfies ApiError);

export async function courseRoutes(app: FastifyInstance) {
  // Live college profile: name + departments served from the in-memory store
  // so the app always reflects the current data.
  app.get("/college", async () => {
    const college = (await getColleges())[0];
    if (!college) {
      return { data: null };
    }
    const departments = await getDepartments(college.id);
    return {
      data: {
        ...college,
        departments,
        departmentCount: departments.length,
      },
    };
  });

  app.get("/courses", async () => {
    const courses = await getCourses();
    const users = await getUsers();
    return {
      data: await Promise.all(
        courses.map(async (course) => {
          const teacher = users.find((u) => u.id === course.teacherId);
          const courseAssignments = await getAssignmentsByCourse(course.id);
          return {
            ...course,
            teacherName: teacher?.displayName ?? "Unassigned",
            studentCount: course.studentIds.length,
            openAssignmentCount: courseAssignments.filter(
              (a) => a.status === "open",
            ).length,
          };
        }),
      ),
    };
  });

  app.get<{ Params: { courseId: string } }>(
    "/courses/:courseId",
    async (request, reply) => {
      const course = await getCourse(request.params.courseId);
      if (!course) {
        return fail(reply, 404, "COURSE_NOT_FOUND", "Course not found");
      }

      const teacher = await getUser(course.teacherId);
      const rosterPromises = course.studentIds.map((id: string) => getUser(id));
      const roster = (await Promise.all(rosterPromises)).filter(
        (u: any): u is User => Boolean(u),
      );
      const courseAssignments = await visibleAssignments(callerOf(request), course);

      return {
        data: {
          course,
          teacher: teacher ?? null,
          roster,
          assignments: courseAssignments,
        },
      };
    },
  );

  app.get<{ Params: { courseId: string } }>(
    "/courses/:courseId/assignments",
    async (request, reply) => {
      const course = await getCourse(request.params.courseId);
      if (!course) {
        return fail(reply, 404, "COURSE_NOT_FOUND", "Course not found");
      }

      return {
        data: (await visibleAssignments(callerOf(request), course)).sort(
          (a, b) => a.dueAt.localeCompare(b.dueAt),
        ),
      };
    },
  );

  app.get<{ Params: { assignmentId: string } }>(
    "/assignments/:assignmentId",
    async (request, reply) => {
      const assignment = await getAssignment(request.params.assignmentId);
      if (!assignment) {
        return fail(reply, 404, "ASSIGNMENT_NOT_FOUND", "Assignment not found");
      }

      const course = await getCourse(assignment.courseId);
      // A draft does not exist for anyone who cannot manage it.
      if (assignment.status === "draft" && !managesCourse(callerOf(request), course)) {
        return fail(reply, 404, "ASSIGNMENT_NOT_FOUND", "Assignment not found");
      }
      return { data: { assignment, course: course ?? null } };
    },
  );

  app.get<{ Params: { assignmentId: string } }>(
    "/assignments/:assignmentId/roster",
    async (request, reply) => {
      const assignment = await getAssignment(request.params.assignmentId);
      if (!assignment) {
        return fail(reply, 404, "ASSIGNMENT_NOT_FOUND", "Assignment not found");
      }

      const course = await getCourse(assignment.courseId);
      if (!course) {
        return fail(reply, 404, "COURSE_NOT_FOUND", "Course not found");
      }
      // The roster shows every student's status, grade and effort score:
      // admins, and the teacher of this course, only.
      if (!managesCourse(callerOf(request), course)) {
        return fail(reply, 403, "FORBIDDEN", "Only the course's teacher or an admin can view the roster");
      }

      const allSubmissions = await getSubmissionsByAssignment(assignment.id);
      const allUsers = await getUsers();
      const roster = course.studentIds.map((studentId: string) => {
        const student = allUsers.find((u) => u.id === studentId);
        const submission = allSubmissions.find(
          (entry) => entry.studentId === studentId,
        );
        return {
          studentId,
          displayName: student?.displayName ?? "Unknown student",
          status: submission?.status ?? "missing",
          submittedAt: submission?.submittedAt ?? null,
          effortScore: submission?.effortScore ?? null,
          grade: submission?.grade ?? null,
        };
      });

      return { data: { assignment, roster } };
    },
  );

  app.post<{
    Params: { assignmentId: string };
    Body: { studentId?: string; attachments?: Attachment[] };
  }>("/assignments/:assignmentId/submissions", async (request, reply) => {
    const assignment = await getAssignment(request.params.assignmentId);
    if (!assignment) {
      return fail(reply, 404, "ASSIGNMENT_NOT_FOUND", "Assignment not found");
    }

    // Students can only submit their own work; staff may submit on a
    // student's behalf by passing studentId.
    const caller = (request as { user?: { id: string; role?: string } }).user;
    const studentId =
      caller?.role === "student" ? caller.id : request.body?.studentId;
    if (!studentId) {
      return fail(reply, 400, "INVALID_BODY", "studentId is required");
    }
    if (
      caller?.role === "student" &&
      request.body?.studentId &&
      request.body.studentId !== caller.id
    ) {
      return fail(reply, 403, "FORBIDDEN", "Students can only submit their own work");
    }

    const student = await getUser(studentId);
    if (!student) {
      return fail(reply, 404, "STUDENT_NOT_FOUND", "Student not found");
    }

    const course = await getCourse(assignment.courseId);
    if (!course?.studentIds.includes(studentId)) {
      return fail(reply, 403, "NOT_ENROLLED", "Student is not enrolled in this course");
    }

    const attachments = request.body?.attachments ?? [];
    if (!Array.isArray(attachments)) {
      return fail(reply, 400, "INVALID_BODY", "attachments must be an array");
    }

    if (assignment.status === "draft") {
      return fail(reply, 409, "ASSIGNMENT_DRAFT", "Assignment is not open for submissions");
    }
    if (assignment.status === "closed") {
      return fail(reply, 409, "ASSIGNMENT_CLOSED", "Assignment is closed for submissions");
    }

    const submittedAt = new Date().toISOString();
    const status: Submission["status"] =
      new Date(assignment.dueAt).getTime() < Date.now() ? "late" : "submitted";

    const existingSubmissions = await getSubmissionsByAssignment(assignment.id);
    const existing = existingSubmissions.find(
      (entry) => entry.studentId === studentId,
    );

    if (existing) {
      await updateSubmission(existing.id, {
        status,
        submittedAt,
        attachments,
      });
      const updated = await getSubmission(existing.id);
      return reply.code(200).send({ data: updated });
    }

    const submission = await createSubmission({
      assignmentId: assignment.id,
      studentId,
      status,
      submittedAt,
      attachments,
    });
    return reply.code(201).send({ data: submission });
  });
}

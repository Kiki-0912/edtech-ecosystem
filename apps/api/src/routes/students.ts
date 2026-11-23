import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { randomUUID } from 'node:crypto';
import {
  getUser,
  getUsers,
  createUser,
  updateUser,
  deleteUser,
  getCourse,
  getCourses,
  getDepartment,
  enrollStudentInDepartment,
  getStudentsByCourse,
  setCourseStudents,
} from '../store/db.js';
import { authenticate } from '../middleware/auth.js';
import { TEXT, bodySchema, rejectInvalidBody } from '../middleware/validation.js';
import type { StudentSummary } from '@edtech/shared';

type AuthRequest = FastifyRequest & { user?: { id: string; role?: string } };

const CREATE_STUDENT_SCHEMA = {
  type: 'object',
  required: ['displayName'],
  properties: {
    displayName: TEXT,
    email: { type: 'string' },
    phone: { type: 'string' },
    rollNumber: { type: 'string' },
    courseId: TEXT,
    departmentId: TEXT,
  },
};

const UPDATE_STUDENT_SCHEMA = {
  type: 'object',
  properties: {
    displayName: TEXT,
    email: { type: 'string' },
    phone: { type: 'string' },
    courseId: TEXT,
  },
};

const invalid = (reply: FastifyReply, code: string, message: string) =>
  reply.code(400).send({ error: { code, message } });

/**
 * Make `courseId` the student's only course. setCourseStudents keeps
 * courses.studentIds, users.courseIds and course channel membership in sync.
 */
async function enrollInOnly(studentId: string, courseId: string): Promise<void> {
  for (const course of await getCourses()) {
    if (course.id !== courseId && course.studentIds.includes(studentId)) {
      await setCourseStudents(course.id, course.studentIds.filter((id) => id !== studentId));
    }
  }
  const target = await getCourse(courseId);
  // Also run when already on the roster, so users.courseIds catches up.
  if (target) await setCourseStudents(courseId, [...target.studentIds, studentId]);
}

const studentsRoutes: FastifyPluginAsync = async (fastify) => {
  // GET /api/v1/students - list all students (admin/teacher). A student gets
  // only their classmates (students sharing a course), as names without
  // contact details: enough for chat, and nobody's phone or email.
  fastify.get(
    '/students',
    { preHandler: [authenticate] },
    async (request, reply) => {
      const users = await getUsers();
      const students = users.filter((u) => u.role === 'student');
      const caller = (request as AuthRequest).user;
      if (caller?.role !== 'student') {
        return reply.send({ data: students });
      }
      const mine = new Set(students.find((u) => u.id === caller.id)?.courseIds ?? []);
      const classmates: StudentSummary[] = students
        .filter((u) => u.id === caller.id || u.courseIds.some((id) => mine.has(id)))
        .map(({ id, displayName, role }) => ({ id, displayName, role }));
      return reply.send({ data: classmates });
    }
  );

  // GET /api/v1/students/:id - get a single student (staff, or a student's own record)
  fastify.get(
    '/students/:id',
    { preHandler: [authenticate] },
    async (request, reply) => {
      const req = request as AuthRequest;
      const id = (req.params as { id: string }).id;
      if (req.user?.role === 'student' && req.user.id !== id) {
        return reply
          .code(403)
          .send({ error: { code: 'FORBIDDEN', message: 'Students can only view their own record' } });
      }
      const user = (await getUsers()).find((u) => u.id === id);
      if (!user || user.role !== 'student') {
        return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Student not found' } });
      }
      return reply.send({ data: user });
    }
  );

  // POST /api/v1/students - create a new student (admin only)
  fastify.post(
    '/students',
    { preHandler: [authenticate], ...bodySchema(CREATE_STUDENT_SCHEMA) },
    async (request, reply) => {
      const req = request as AuthRequest;
      const caller = req.user;
      if (caller?.role !== 'admin') {
        return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Admin only' } });
      }
      if (rejectInvalidBody(request, reply)) return reply;
      const body = request.body as {
        displayName: string;
        email?: string;
        phone?: string;
        rollNumber?: string;
        courseId?: string;
        departmentId?: string;
      };
      const email = body.email?.trim() ?? '';
      const phone = body.phone?.trim() ?? '';
      if (!email && !phone) {
        return invalid(reply, 'INVALID_BODY', 'Phone or email is required');
      }
      // Check references before writing, so a bad id leaves nothing behind.
      if (body.courseId && !(await getCourse(body.courseId))) {
        return invalid(reply, 'INVALID_REFERENCE', 'Course not found');
      }
      if (body.departmentId && !(await getDepartment(body.departmentId))) {
        return invalid(reply, 'INVALID_REFERENCE', 'Department not found');
      }
      const id = randomUUID();
      // A duplicate email or phone is rejected by the store (409 CONFLICT).
      await createUser({
        id,
        displayName: body.displayName.trim(),
        email,
        phone,
        role: 'student',
        courseIds: [],
        passwordHash: '',
        isPhoneVerified: 0,
        createdAt: new Date().toISOString(),
      });
      if (body.courseId) await enrollInOnly(id, body.courseId);

      // If department specified, enroll student
      if (body.departmentId) {
        await enrollStudentInDepartment({
          studentId: id,
          departmentId: body.departmentId,
          enrolledBy: caller.id,
        });
      }

      return reply.code(201).send({ data: await getUser(id) });
    }
  );

  // PUT /api/v1/students/:id - update a student (admin only). A courseId
  // moves the student into that one course (out of any others).
  fastify.put(
    '/students/:id',
    { preHandler: [authenticate], ...bodySchema(UPDATE_STUDENT_SCHEMA) },
    async (request, reply) => {
      const req = request as AuthRequest;
      const caller = req.user;
      if (caller?.role !== 'admin') {
        return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Admin only' } });
      }
      if (rejectInvalidBody(request, reply)) return reply;
      const body = request.body as Partial<{
        displayName: string;
        email: string;
        phone: string;
        courseId: string;
      }>;
      const studentId = (req.params as { id: string }).id;
      const student = await getUser(studentId);
      if (!student || student.role !== 'student') {
        return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Student not found' } });
      }
      if (body.courseId !== undefined && !(await getCourse(body.courseId))) {
        return invalid(reply, 'INVALID_REFERENCE', 'Course not found');
      }
      const email = body.email === undefined ? student.email : body.email.trim();
      const phone = body.phone === undefined ? student.phone : body.phone.trim();
      if (!email && !phone) {
        return invalid(reply, 'INVALID_BODY', 'Phone or email is required');
      }
      // A duplicate email or phone is rejected by the store (409 CONFLICT).
      await updateUser(studentId, {
        displayName: body.displayName?.trim(),
        email: body.email === undefined ? undefined : email,
        phone: body.phone === undefined ? undefined : phone,
      });
      if (body.courseId !== undefined) await enrollInOnly(studentId, body.courseId);

      return reply.send({ data: await getUser(studentId) });
    }
  );

  // DELETE /api/v1/students/:id - delete a student (admin only). Same store
  // delete as the admin console, so roster, channel, submission, attendance,
  // telemetry and department rows go with the account.
  fastify.delete(
    '/students/:id',
    { preHandler: [authenticate] },
    async (request, reply) => {
      const req = request as AuthRequest;
      const caller = req.user;
      if (caller?.role !== 'admin') {
        return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Admin only' } });
      }
      const studentId = (req.params as { id: string }).id;
      const student = await getUser(studentId);
      if (!student || student.role !== 'student') {
        return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Student not found' } });
      }
      const result = await deleteUser(studentId);
      if (result === 'not_found') {
        return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Student not found' } });
      }
      if (result !== 'deleted') {
        return reply
          .code(409)
          .send({ error: { code: 'USER_IN_USE', message: 'This student cannot be deleted' } });
      }
      return reply.send({ data: { success: true } });
    }
  );

  // GET /api/v1/courses/:courseId/students - get students in a course
  fastify.get(
    '/courses/:courseId/students',
    { preHandler: [authenticate] },
    async (request, reply) => {
      const req = request as AuthRequest;
      const students = await getStudentsByCourse((req.params as { courseId: string }).courseId);
      return reply.send({ data: students });
    }
  );
};

export default studentsRoutes;

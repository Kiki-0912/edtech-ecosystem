import type { FastifyPluginAsync } from 'fastify';
import type { AttendanceStatus } from '@edtech/shared';
import {
  getAttendanceRecords,
  getAttendanceRecord,
  upsertAttendanceRecord,
  getStudentsByCourse,
  getCourse,
  getUsers,
} from '../store/db.js';
import { authenticate, requireRoles } from '../middleware/auth.js';
import { callerOf, managesCourse, managesCourseId, readableCourseIds } from '../middleware/scope.js';
import { TEXT, bodySchema, rejectInvalidBody } from '../middleware/validation.js';

const STATUSES: AttendanceStatus[] = ['present', 'absent', 'late', 'excused'];

const RECORD_SCHEMA = {
  type: 'object',
  required: ['courseId', 'studentId', 'date', 'status'],
  properties: {
    courseId: TEXT,
    studentId: TEXT,
    date: TEXT,
    status: { type: 'string', enum: STATUSES },
    notes: { type: 'string' },
  },
};

const BULK_SCHEMA = {
  type: 'object',
  required: ['courseId', 'date', 'records'],
  properties: {
    courseId: TEXT,
    date: TEXT,
    records: {
      type: 'array',
      items: {
        type: 'object',
        required: ['studentId', 'status'],
        properties: {
          studentId: TEXT,
          status: { type: 'string', enum: STATUSES },
          notes: { type: 'string' },
        },
      },
    },
  },
};

const forbidden = { error: { code: 'FORBIDDEN', message: 'You do not have access to this course' } };

const attendanceRoutes: FastifyPluginAsync = async (fastify) => {
  // GET /api/v1/attendance - list attendance records
  // Query: courseId, date. Students see only their own records, teachers only
  // the courses they teach, admins everything.
  fastify.get(
    '/attendance',
    { preHandler: [authenticate] },
    async (request, reply) => {
      const caller = callerOf(request);
      const { courseId, date } = request.query as { courseId?: string; date?: string };
      let records = await getAttendanceRecords(courseId, date);
      if (caller?.role === 'student') {
        records = records.filter((r) => r.studentId === caller.id);
      } else if (caller?.role !== 'admin') {
        if (courseId && !(await managesCourseId(caller, courseId))) {
          return reply.code(403).send(forbidden);
        }
        const taught = await readableCourseIds(caller);
        records = records.filter((r) => taught.has(r.courseId));
      }
      return reply.send({ data: records });
    }
  );

  // GET /api/v1/attendance/:id - single record (same scoping as the list)
  fastify.get(
    '/attendance/:id',
    { preHandler: [authenticate] },
    async (request, reply) => {
      const caller = callerOf(request);
      const record = await getAttendanceRecord((request.params as { id: string }).id);
      if (!record) {
        return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Attendance record not found' } });
      }
      const allowed =
        caller?.role === 'student'
          ? record.studentId === caller.id
          : await managesCourseId(caller, record.courseId);
      if (!allowed) {
        return reply
          .code(403)
          .send({ error: { code: 'FORBIDDEN', message: 'You do not have access to this record' } });
      }
      return reply.send({ data: record });
    }
  );

  // POST /api/v1/attendance - create or update attendance (admin, or the course's teacher)
  fastify.post(
    '/attendance',
    { preHandler: [authenticate, requireRoles('admin', 'teacher')], ...bodySchema(RECORD_SCHEMA) },
    async (request, reply) => {
      if (rejectInvalidBody(request, reply)) return reply;
      const caller = callerOf(request);
      const body = request.body as {
        courseId: string;
        studentId: string;
        date: string; // YYYY-MM-DD
        status: AttendanceStatus;
        notes?: string;
      };
      if (!(await managesCourseId(caller, body.courseId))) {
        return reply.code(403).send(forbidden);
      }
      const record = await upsertAttendanceRecord({
        courseId: body.courseId,
        studentId: body.studentId,
        date: body.date,
        status: body.status,
        markedBy: caller?.id ?? 'system',
        notes: body.notes,
      });
      return reply.code(201).send({ data: record });
    }
  );

  // POST /api/v1/attendance/bulk - bulk mark attendance for a course/date
  fastify.post(
    '/attendance/bulk',
    { preHandler: [authenticate, requireRoles('admin', 'teacher')], ...bodySchema(BULK_SCHEMA) },
    async (request, reply) => {
      if (rejectInvalidBody(request, reply)) return reply;
      const caller = callerOf(request);
      const body = request.body as {
        courseId: string;
        date: string; // YYYY-MM-DD
        records: { studentId: string; status: AttendanceStatus; notes?: string }[];
      };
      if (!(await managesCourseId(caller, body.courseId))) {
        return reply.code(403).send(forbidden);
      }
      // Check every reference first, so a bad row cannot leave a partial write.
      if (!(await getCourse(body.courseId))) {
        return reply
          .code(400)
          .send({ error: { code: 'INVALID_REFERENCE', message: 'Course not found' } });
      }
      const userIds = new Set((await getUsers()).map((u) => u.id));
      const unknown = body.records.find((r) => !userIds.has(r.studentId));
      if (unknown) {
        return reply.code(400).send({
          error: { code: 'INVALID_REFERENCE', message: `Unknown student: ${unknown.studentId}` },
        });
      }
      const results = [];
      for (const r of body.records) {
        results.push(
          await upsertAttendanceRecord({
            courseId: body.courseId,
            studentId: r.studentId,
            date: body.date,
            status: r.status,
            markedBy: caller?.id ?? 'system',
            notes: r.notes,
          })
        );
      }
      return reply.code(201).send({ data: results });
    }
  );

  // GET /api/v1/attendance/course/:courseId/students - students with attendance for a date.
  // Staff who manage the course see the whole roster; a student sees only their own row.
  fastify.get(
    '/attendance/course/:courseId/students',
    { preHandler: [authenticate] },
    async (request, reply) => {
      const caller = callerOf(request);
      const { courseId } = request.params as { courseId: string };
      const { date } = request.query as { date?: string };
      let students = await getStudentsByCourse(courseId);
      let records = await getAttendanceRecords(courseId, date);
      if (caller?.role === 'student') {
        students = students.filter((s) => s.id === caller.id);
        records = records.filter((r) => r.studentId === caller.id);
      } else if (!managesCourse(caller, await getCourse(courseId)) && caller?.role !== 'admin') {
        return reply.code(403).send(forbidden);
      }
      const recordMap = new Map(records.map((r) => [r.studentId, r]));
      const result = students.map((s) => ({
        id: s.id,
        displayName: s.displayName,
        email: s.email,
        phone: s.phone,
        status: recordMap.get(s.id)?.status ?? 'absent',
        notes: recordMap.get(s.id)?.notes ?? '',
        date,
      }));
      return reply.send({ data: result });
    }
  );
};

export default attendanceRoutes;

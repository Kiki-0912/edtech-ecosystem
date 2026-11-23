import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { randomUUID } from 'node:crypto';
import {
  createUser,
  enrollStudentInDepartment,
  getAttendanceRecords,
  getCourse,
  getStudentsByCourse,
  getTeacherNotes,
  getUsers,
  setCourseStudents,
} from '../store/db.js';
import { authenticate, requireRoles } from '../middleware/auth.js';
import { bodySchema, rejectInvalidBody } from '../middleware/validation.js';

const IMPORT_SCHEMA = {
  type: 'object',
  required: ['rows'],
  properties: {
    courseId: { type: ['string', 'null'] },
    rows: {
      type: 'array',
      // Missing cells are reported per row below rather than failing the file.
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          rollNumber: { type: 'string' },
          contact: { type: 'string' },
          departmentId: { type: ['string', 'null'] },
        },
      },
    },
  },
};

type AuthRequest = FastifyRequest & { user?: { id: string; role?: string } };

const excelRoutes: FastifyPluginAsync = async (fastify) => {
  // POST /api/v1/excel/import/students - import students from Excel
  // Body: { courseId: string, rows: StudentImportRow[] }
  fastify.post(
    '/excel/import/students',
    { preHandler: [authenticate], ...bodySchema(IMPORT_SCHEMA) },
    async (request, reply) => {
      const req = request as AuthRequest;
      const caller = req.user;
      if (caller?.role !== 'admin') {
        return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Admin only' } });
      }
      if (rejectInvalidBody(request, reply)) return reply;
      const body = request.body as {
        courseId?: string | null;
        rows: { name?: string; rollNumber?: string; contact?: string; departmentId?: string | null }[];
      };
      if (body.courseId && !(await getCourse(body.courseId))) {
        return reply
          .code(400)
          .send({ error: { code: 'INVALID_REFERENCE', message: 'Course not found' } });
      }
      const imported: any[] = [];
      const errors: { row: number; message: string }[] = [];

      for (let i = 0; i < body.rows.length; i++) {
        const row = body.rows[i];
        const rowNum = i + 2; // header is row 1
        try {
          if (!row.name || !row.rollNumber || !row.contact) {
            errors.push({ row: rowNum, message: 'Missing name, roll number, or contact' });
            continue;
          }
          const id = randomUUID();
          const now = new Date().toISOString();
          await createUser({
            id,
            displayName: row.name,
            email: `${row.rollNumber.toLowerCase().replace(/\s/g, '')}@example.edu`,
            phone: row.contact,
            role: 'student',
            courseIds: [],
            passwordHash: '',
            isPhoneVerified: 0,
            createdAt: now,
          });
          if (body.courseId) {
            // Keeps courses.studentIds, users.courseIds and channels in sync.
            const course = await getCourse(body.courseId);
            if (course) await setCourseStudents(course.id, [...course.studentIds, id]);
          }
          if (row.departmentId) {
            await enrollStudentInDepartment({
              studentId: id,
              departmentId: row.departmentId,
              enrolledBy: caller?.id ?? id,
            });
          }
          imported.push({ id, name: row.name, rollNumber: row.rollNumber, contact: row.contact });
        } catch (err: any) {
          errors.push({ row: rowNum, message: err?.message ?? 'Unknown error' });
        }
      }

      return reply.code(201).send({ data: { imported: imported.length, errors, students: imported } });
    }
  );

  // GET /api/v1/excel/export/students - export students to Excel-compatible JSON
  // Query: courseId
  fastify.get(
    '/excel/export/students',
    { preHandler: [authenticate] },
    async (request, reply) => {
      const req = request as AuthRequest;
      const caller = req.user;
      if (caller?.role !== 'admin' && caller?.role !== 'teacher') {
        return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Admin or teacher only' } });
      }
      const { courseId } = request.query as { courseId?: string };
      let students = (await getUsers()).filter((u) => u.role === 'student');
      if (courseId) {
        students = await getStudentsByCourse(courseId);
      }
      const rows = students.map((s) => ({
        name: s.displayName,
        rollNumber: s.id, // using id as roll number placeholder
        contact: s.phone,
        email: s.email,
        courseIds: JSON.stringify(s.courseIds),
      }));
      return reply.send({ data: { headers: ['name', 'rollNumber', 'contact', 'email', 'courseIds'], rows } });
    }
  );

  // GET /api/v1/excel/export/attendance - export attendance to Excel-compatible JSON
  // Query: courseId, date
  fastify.get(
    '/excel/export/attendance',
    { preHandler: [authenticate, requireRoles('admin', 'teacher')] },
    async (request, reply) => {
      const { courseId, date } = request.query as { courseId?: string; date?: string };
      const records = await getAttendanceRecords(courseId, date);
      const rows = records.map((r) => ({
        id: r.id,
        courseId: r.courseId,
        studentId: r.studentId,
        date: r.date,
        status: r.status,
        markedBy: r.markedBy,
        notes: r.notes,
      }));
      return reply.send({ data: { headers: ['id', 'courseId', 'studentId', 'date', 'status', 'markedBy', 'notes'], rows } });
    }
  );

  // GET /api/v1/excel/export/notes - export teacher notes to Excel-compatible JSON
  // Query: courseId, courseCode
  fastify.get(
    '/excel/export/notes',
    { preHandler: [authenticate, requireRoles('admin', 'teacher')] },
    async (request, reply) => {
      const { courseId, courseCode } = request.query as { courseId?: string; courseCode?: string };
      const notes = await getTeacherNotes(courseId, courseCode);
      const rows = notes.map((n) => ({
        id: n.id,
        courseId: n.courseId,
        bookName: n.bookName,
        courseCode: n.courseCode,
        title: n.title,
        content: n.content,
        authorId: n.authorId,
        createdAt: n.createdAt,
        updatedAt: n.updatedAt,
      }));
      return reply.send({ data: { headers: ['id', 'courseId', 'bookName', 'courseCode', 'title', 'content', 'authorId', 'createdAt', 'updatedAt'], rows } });
    }
  );
};

export default excelRoutes;

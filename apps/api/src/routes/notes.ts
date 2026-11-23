import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import {
  getTeacherNotes,
  getTeacherNote,
  upsertTeacherNote,
  deleteTeacherNote,
} from '../store/db.js';
import { authenticate, requireRoles } from '../middleware/auth.js';
import { TEXT, bodySchema, rejectInvalidBody } from '../middleware/validation.js';

const NOTE_PROPERTIES = {
  bookName: TEXT,
  courseCode: TEXT,
  title: TEXT,
  content: { type: 'string' },
};
const CREATE_NOTE_SCHEMA = {
  type: 'object',
  required: ['courseId', 'bookName', 'courseCode', 'title'],
  properties: { courseId: TEXT, ...NOTE_PROPERTIES },
};
const UPDATE_NOTE_SCHEMA = { type: 'object', properties: NOTE_PROPERTIES };

type AuthRequest = FastifyRequest & { user?: { id: string; role?: string } };

const notesRoutes: FastifyPluginAsync = async (fastify) => {
  // GET /api/v1/notes - list teacher notes
  // Query: courseId, courseCode
  fastify.get(
    '/notes',
    { preHandler: [authenticate] },
    async (request, reply) => {
      const { courseId, courseCode } = request.query as { courseId?: string; courseCode?: string };
      const notes = await getTeacherNotes(courseId, courseCode);
      return reply.send({ data: notes });
    }
  );

  // GET /api/v1/notes/:id - single note
  fastify.get(
    '/notes/:id',
    { preHandler: [authenticate] },
    async (request, reply) => {
      const req = request as AuthRequest;
      const note = await getTeacherNote((req.params as { id: string }).id);
      if (!note) {
        return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Note not found' } });
      }
      return reply.send({ data: note });
    }
  );

  // POST /api/v1/notes - create a note (teacher/admin only)
  fastify.post(
    '/notes',
    { preHandler: [authenticate, requireRoles('admin', 'teacher')], ...bodySchema(CREATE_NOTE_SCHEMA) },
    async (request, reply) => {
      if (rejectInvalidBody(request, reply)) return reply;
      const req = request as AuthRequest;
      const caller = req.user;
      // An unknown courseId is rejected by the store (400 INVALID_REFERENCE).
      const body = request.body as {
        courseId: string;
        bookName: string;
        courseCode: string;
        title: string;
        content?: string;
      };
      const note = await upsertTeacherNote({
        courseId: body.courseId,
        bookName: body.bookName,
        courseCode: body.courseCode,
        title: body.title,
        content: body.content ?? '',
        authorId: caller?.id ?? 'system',
      });
      return reply.code(201).send({ data: note });
    }
  );

  // PUT /api/v1/notes/:id - update a note (author or admin)
  fastify.put(
    '/notes/:id',
    { preHandler: [authenticate], ...bodySchema(UPDATE_NOTE_SCHEMA) },
    async (request, reply) => {
      const req = request as AuthRequest;
      const caller = req.user;
      const note = await getTeacherNote((req.params as { id: string }).id);
      if (!note) {
        return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Note not found' } });
      }
      if (caller?.role !== 'admin' && note.authorId !== caller?.id) {
        return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Not the author' } });
      }
      if (rejectInvalidBody(request, reply)) return reply;
      const body = request.body as Partial<{
        bookName: string;
        courseCode: string;
        title: string;
        content: string;
      }>;
      const updated = await upsertTeacherNote({
        id: note.id,
        courseId: note.courseId,
        bookName: body.bookName ?? note.bookName,
        courseCode: body.courseCode ?? note.courseCode,
        title: body.title ?? note.title,
        content: body.content ?? note.content,
        authorId: note.authorId,
      });
      return reply.send({ data: updated });
    }
  );

  // DELETE /api/v1/notes/:id - delete a note (author or admin)
  fastify.delete(
    '/notes/:id',
    { preHandler: [authenticate] },
    async (request, reply) => {
      const req = request as AuthRequest;
      const caller = req.user;
      const note = await getTeacherNote((req.params as { id: string }).id);
      if (!note) {
        return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Note not found' } });
      }
      if (caller?.role !== 'admin' && note.authorId !== caller?.id) {
        return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Not the author' } });
      }
      await deleteTeacherNote(note.id);
      return reply.send({ data: { success: true } });
    }
  );
};

export default notesRoutes;

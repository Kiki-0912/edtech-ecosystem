// Data scoping helpers: which courses a caller may read or manage.
import type { FastifyRequest } from "fastify";
import type { StudentSummary } from "@edtech/shared";
import type { Course } from "../store/db";
import { getCourse, getCourses, getUser } from "../store/db";

export type Caller = { id: string; role?: string };

/** The authenticated caller set by `authenticate`, if any. */
export function callerOf(request: FastifyRequest): Caller | undefined {
  return (request as FastifyRequest & { user?: Caller }).user;
}

/** True if the caller is an admin, or the teacher of `course`. */
export function managesCourse(caller: Caller | undefined, course: Course | undefined): boolean {
  if (!caller || !course) return false;
  if (caller.role === "admin") return true;
  return caller.role === "teacher" && course.teacherId === caller.id;
}

/** True if the caller may manage the course with this id (admins: any existing course). */
export async function managesCourseId(
  caller: Caller | undefined,
  courseId: string | null | undefined,
): Promise<boolean> {
  if (caller?.role === "admin") return true;
  if (!courseId) return false;
  return managesCourse(caller, await getCourse(courseId));
}

/**
 * The course ids whose data the caller may read: every course for admins, the
 * courses they teach for teachers, and their enrolled courses for students.
 */
export async function readableCourseIds(caller: Caller | undefined): Promise<Set<string>> {
  if (!caller) return new Set();
  const courses = await getCourses();
  if (caller.role === "admin") return new Set(courses.map((course) => course.id));
  if (caller.role === "teacher") {
    return new Set(
      courses.filter((course) => course.teacherId === caller.id).map((course) => course.id),
    );
  }
  const enrolled = new Set((await getUser(caller.id))?.courseIds ?? []);
  for (const course of courses) {
    if (course.studentIds.includes(caller.id)) enrolled.add(course.id);
  }
  return enrolled;
}

/** True if the caller may read the course: admins, its teacher, and enrolled students. */
export async function readsCourseId(
  caller: Caller | undefined,
  courseId: string | null | undefined,
): Promise<boolean> {
  if (!caller || !courseId) return false;
  if (caller.role === "admin") return true;
  return (await readableCourseIds(caller)).has(courseId);
}

/**
 * The student ids whose records the caller may see in full: every student for
 * admins, the students on their courses' rosters for teachers, and just
 * themselves for students.
 */
export async function visibleStudentIds(caller: Caller | undefined): Promise<Set<string> | "all"> {
  if (!caller) return new Set();
  if (caller.role === "admin") return "all";
  if (caller.role === "teacher") {
    const ids = new Set<string>();
    for (const course of await getCourses()) {
      if (course.teacherId === caller.id) course.studentIds.forEach((id) => ids.add(id));
    }
    return ids;
  }
  return new Set([caller.id]);
}

/** A name-only view of a user, for callers who may not see contact details. */
export function toSummary(user: StudentSummary): StudentSummary {
  return { id: user.id, displayName: user.displayName, role: user.role };
}

// Data scoping helpers: which courses a caller may read or manage.
import type { FastifyRequest } from "fastify";
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

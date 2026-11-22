// Data-access facade used by every route.
//
// With DATABASE_URL set, data lives in Postgres (`pg-store.ts`): migrations run
// and an empty database is seeded on first start. Without it, the API falls back
// to the seeded in-memory store (`memory-store.ts`), which tests and offline
// local development use. Both stores expose the same async functions.
import type pg from "pg";
import { config } from "../config";
import { hashPassword } from "../services/password";
import * as memory from "./memory-store";
import { createPgStore, createPool, runMigrations, seedDatabase } from "./pg-store";

export type * from "./memory-store";

type AnyFn = (...args: any[]) => any;
type Asyncified<T> = {
  [K in keyof T as T[K] extends AnyFn ? K : never]: T[K] extends (...args: infer A) => infer R
    ? (...args: A) => Promise<Awaited<R>>
    : never;
};

/** Everything a store must implement: the in-memory functions, made async. */
export type Store = Omit<Asyncified<typeof memory>, "initDb" | "buildSeedRows">;

export type StoreKind = "memory" | "postgres";

let current: Store | null = null;
let currentKind: StoreKind = "memory";
let pool: pg.Pool | null = null;
let initPromise: Promise<void> | null = null;

function memoryStore(): Store {
  const wrapped: Record<string, AnyFn> = {};
  for (const [name, value] of Object.entries(memory)) {
    if (typeof value !== "function" || name === "initDb" || name === "buildSeedRows") {
      continue;
    }
    wrapped[name] = async (...args: unknown[]) => (value as AnyFn)(...args);
  }
  return wrapped as Store;
}

/** Seed credentials from env, so a deployment need not use the public demo password. */
function seedOptions(): memory.SeedOptions {
  return {
    passwordHash: config.seedDemoPassword ? hashPassword(config.seedDemoPassword) : undefined,
    adminEmail: config.seedAdminEmail ?? undefined,
  };
}

async function connect(): Promise<void> {
  if (!config.databaseUrl) {
    await memory.initDb(seedOptions());
    current = memoryStore();
    currentKind = "memory";
    return;
  }
  const nextPool = createPool(config.databaseUrl);
  try {
    await runMigrations(nextPool);
    await seedDatabase(nextPool, { includeDemo: config.seedDemoData, ...seedOptions() });
  } catch (error) {
    await nextPool.end().catch(() => {});
    throw error;
  }
  pool = nextPool;
  current = createPgStore(nextPool);
  currentKind = "postgres";
}

/** Connect, migrate and seed once per process. Concurrent callers share it. */
export function initDb(): Promise<void> {
  initPromise ??= connect().catch((error) => {
    initPromise = null;
    throw error;
  });
  return initPromise;
}

/** Release the connection pool (tests, graceful shutdown). */
export async function closeDb(): Promise<void> {
  const closing = pool;
  pool = null;
  current = null;
  initPromise = null;
  if (closing) await closing.end();
}

export function storeKind(): StoreKind {
  return currentKind;
}

/** Round-trip check for /health. Memory is always reachable. */
export async function pingDb(): Promise<boolean> {
  if (!pool) return true;
  try {
    await pool.query("SELECT 1");
    return true;
  } catch {
    return false;
  }
}

function active(): Store {
  if (!current) throw new Error("Data store used before initDb() resolved");
  return current;
}

export const getUsers: Store["getUsers"] = (...args) => active().getUsers(...args);
export const getUser: Store["getUser"] = (...args) => active().getUser(...args);
export const getUserByPhone: Store["getUserByPhone"] = (...args) => active().getUserByPhone(...args);
export const getUserAuthByPhone: Store["getUserAuthByPhone"] = (...args) => active().getUserAuthByPhone(...args);
export const getUserAuthByEmail: Store["getUserAuthByEmail"] = (...args) => active().getUserAuthByEmail(...args);
export const createUser: Store["createUser"] = (...args) => active().createUser(...args);
export const updateUser: Store["updateUser"] = (...args) => active().updateUser(...args);
export const getCourses: Store["getCourses"] = (...args) => active().getCourses(...args);
export const getCourse: Store["getCourse"] = (...args) => active().getCourse(...args);
export const getAssignmentsByCourse: Store["getAssignmentsByCourse"] = (...args) => active().getAssignmentsByCourse(...args);
export const addStudentToCourse: Store["addStudentToCourse"] = (...args) => active().addStudentToCourse(...args);
export const removeStudentFromCourse: Store["removeStudentFromCourse"] = (...args) => active().removeStudentFromCourse(...args);
export const getColleges: Store["getColleges"] = (...args) => active().getColleges(...args);
export const getCollege: Store["getCollege"] = (...args) => active().getCollege(...args);
export const getDepartments: Store["getDepartments"] = (...args) => active().getDepartments(...args);
export const getDepartment: Store["getDepartment"] = (...args) => active().getDepartment(...args);
export const createDepartment: Store["createDepartment"] = (...args) => active().createDepartment(...args);
export const updateDepartment: Store["updateDepartment"] = (...args) => active().updateDepartment(...args);
export const deleteDepartment: Store["deleteDepartment"] = (...args) => active().deleteDepartment(...args);
export const getAssignment: Store["getAssignment"] = (...args) => active().getAssignment(...args);
export const getSubmissionsByAssignment: Store["getSubmissionsByAssignment"] = (...args) => active().getSubmissionsByAssignment(...args);
export const getSubmission: Store["getSubmission"] = (...args) => active().getSubmission(...args);
export const createSubmission: Store["createSubmission"] = (...args) => active().createSubmission(...args);
export const updateSubmission: Store["updateSubmission"] = (...args) => active().updateSubmission(...args);
export const getCalendarEvents: Store["getCalendarEvents"] = (...args) => active().getCalendarEvents(...args);
export const createCalendarEvent: Store["createCalendarEvent"] = (...args) => active().createCalendarEvent(...args);
export const updateCalendarEvent: Store["updateCalendarEvent"] = (...args) => active().updateCalendarEvent(...args);
export const deleteCalendarEvent: Store["deleteCalendarEvent"] = (...args) => active().deleteCalendarEvent(...args);
export const getChannelsByCourse: Store["getChannelsByCourse"] = (...args) => active().getChannelsByCourse(...args);
export const getChannel: Store["getChannel"] = (...args) => active().getChannel(...args);
export const getMessages: Store["getMessages"] = (...args) => active().getMessages(...args);
export const createMessage: Store["createMessage"] = (...args) => active().createMessage(...args);
export const getTelemetryBatches: Store["getTelemetryBatches"] = (...args) => active().getTelemetryBatches(...args);
export const hasTelemetryBatch: Store["hasTelemetryBatch"] = (...args) => active().hasTelemetryBatch(...args);
export const createTelemetryBatch: Store["createTelemetryBatch"] = (...args) => active().createTelemetryBatch(...args);
export const getEffortScore: Store["getEffortScore"] = (...args) => active().getEffortScore(...args);
export const setEffortScore: Store["setEffortScore"] = (...args) => active().setEffortScore(...args);
export const getIntegrityFlags: Store["getIntegrityFlags"] = (...args) => active().getIntegrityFlags(...args);
export const setIntegrityFlags: Store["setIntegrityFlags"] = (...args) => active().setIntegrityFlags(...args);
export const createSmsCode: Store["createSmsCode"] = (...args) => active().createSmsCode(...args);
export const verifySmsCode: Store["verifySmsCode"] = (...args) => active().verifySmsCode(...args);
export const markPhoneVerified: Store["markPhoneVerified"] = (...args) => active().markPhoneVerified(...args);
export const getAttendanceRecords: Store["getAttendanceRecords"] = (...args) => active().getAttendanceRecords(...args);
export const getAttendanceRecord: Store["getAttendanceRecord"] = (...args) => active().getAttendanceRecord(...args);
export const upsertAttendanceRecord: Store["upsertAttendanceRecord"] = (...args) => active().upsertAttendanceRecord(...args);
export const getTeacherNotes: Store["getTeacherNotes"] = (...args) => active().getTeacherNotes(...args);
export const getTeacherNote: Store["getTeacherNote"] = (...args) => active().getTeacherNote(...args);
export const upsertTeacherNote: Store["upsertTeacherNote"] = (...args) => active().upsertTeacherNote(...args);
export const deleteTeacherNote: Store["deleteTeacherNote"] = (...args) => active().deleteTeacherNote(...args);
export const getStudentDepartments: Store["getStudentDepartments"] = (...args) => active().getStudentDepartments(...args);
export const enrollStudentInDepartment: Store["enrollStudentInDepartment"] = (...args) => active().enrollStudentInDepartment(...args);
export const unenrollStudentFromDepartment: Store["unenrollStudentFromDepartment"] = (...args) => active().unenrollStudentFromDepartment(...args);
export const getStudentsByDepartment: Store["getStudentsByDepartment"] = (...args) => active().getStudentsByDepartment(...args);
export const getDepartmentsByStudent: Store["getDepartmentsByStudent"] = (...args) => active().getDepartmentsByStudent(...args);
export const getStudentsByCourse: Store["getStudentsByCourse"] = (...args) => active().getStudentsByCourse(...args);

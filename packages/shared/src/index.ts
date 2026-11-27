export type Role = "student" | "teacher" | "admin";

export const AI_PLATFORM_HOSTS = [
  "chatgpt.com",
  "chat.openai.com",
  "claude.ai",
  "gemini.google.com",
  "copilot.microsoft.com",
  "perplexity.ai",
] as const;

export interface User {
  id: string;
  displayName: string;
  email: string;
  phone: string;
  role: Role;
  courseIds: string[];
  passwordHash?: string;
  isPhoneVerified?: boolean;
  /** False once an admin disables the account (sign-in and tokens are refused). */
  isActive?: boolean;
  createdAt: string;
}

/**
 * What GET /students returns to a student caller: their classmates (students
 * sharing a course, plus themself), without contact details. Staff get `User`s.
 */
export type StudentSummary = Pick<User, "id" | "displayName" | "role">;

export interface Course {
  id: string;
  title: string;
  code: string;
  teacherId: string;
  studentIds: string[];
  term: string;
  createdAt: string;
}

export interface College {
  id: string;
  name: string;
  shortName: string;
  createdAt: string;
}

/** Programme panel headings as printed on the CTTC admissions flyer. */
export type DepartmentCategory =
  | "3 Years"
  | "2 Years"
  | "6 Months"
  | "2 Years Paramedical";

export interface Department {
  id: string;
  collegeId: string;
  name: string;
  code: string;
  category: DepartmentCategory;
  /** 36 = DAE, 24 = certificates/paramedical, 6 = short courses. */
  durationMonths: number;
  createdAt: string;
}

export type AssignmentStatus = "draft" | "open" | "closed";
export type SubmissionStatus = "pending" | "submitted" | "graded" | "late" | "missing";

export interface Attachment {
  id: string;
  fileName: string;
  mimeType: string;
  sizeBytes: number;
  url: string;
}

export interface Assignment {
  id: string;
  courseId: string;
  title: string;
  brief: string;
  dueAt: string;
  status: AssignmentStatus;
  createdAt: string;
}

/**
 * Body of POST /courses/:courseId/assignments (admins, and the course's teacher).
 * `title` is trimmed (1-200 chars); `brief` is 0-10000 chars (default "");
 * `dueAt` must parse as a date and is stored exactly as sent; `status` defaults
 * to "open". Drafts are hidden from everyone who does not manage the course.
 */
export interface AssignmentCreate {
  title: string;
  brief?: string;
  dueAt: string;
  status?: AssignmentStatus;
}

/** Body of PATCH /assignments/:assignmentId: any non-empty subset of the create fields. */
export type AssignmentUpdate = Partial<Required<AssignmentCreate>>;

export interface Submission {
  id: string;
  assignmentId: string;
  studentId: string;
  status: SubmissionStatus;
  submittedAt: string | null;
  attachments: Attachment[];
  grade: number | null;
  effortScore: number | null;
}

export type CalendarEventKind = "assignment" | "quiz" | "class" | "institution";

export interface CalendarEvent {
  id: string;
  courseId: string | null;
  departmentId?: string | null;
  /**
   * Set on the deadline event the API keeps in sync with an assignment (none
   * while it is a draft). Such events cannot be edited or deleted through
   * /calendar (409 ASSIGNMENT_EVENT); edit the assignment instead.
   */
  assignmentId: string | null;
  title: string;
  kind: CalendarEventKind;
  startsAt: string;
  endsAt: string | null;
}

export type ChatChannelKind = "announcement" | "discussion";

export interface ChatChannel {
  id: string;
  courseId: string;
  name: string;
  kind: ChatChannelKind;
  memberIds: string[];
}

export interface ChatMessage {
  id: string;
  channelId: string;
  authorId: string;
  body: string;
  sentAt: string;
}

export type TelemetryEventType =
  | "keystroke"
  | "cursor"
  | "paste"
  | "focus"
  | "blur"
  | "ai_tab_switch";

export interface TelemetryEvent {
  id: string;
  sessionId: string;
  assignmentId: string;
  studentId: string;
  type: TelemetryEventType;
  occurredAt: string;
  payload: Record<string, number | string | boolean>;
}

export interface SignedTelemetryBatch {
  batchId: string;
  studentId: string;
  assignmentId: string;
  events: TelemetryEvent[];
  clientSignature: string;
  clientPublicKey: string;
  createdAt: string;
}

export interface EffortScore {
  sessionId: string;
  assignmentId: string;
  studentId: string;
  score: number;
  keystrokes: number;
  pastes: number;
  pasteVolume: number;
  aiTabSwitches: number;
  activeSeconds: number;
  computedAt: string;
}

export type IntegrityFlag =
  | "none"
  | "large_paste"
  | "ai_tab_switch"
  | "low_typing_ratio"
  | "telemetry_gap";

export interface IntegrityReport {
  submissionId: string | null;
  assignmentId: string;
  studentId: string;
  effortScore: EffortScore;
  flags: IntegrityFlag[];
  replayAvailable: boolean;
  generatedAt: string;
}

export interface ApiError {
  error: {
    code: string;
    message: string;
  };
}

export interface ApiResponse<T> {
  data: T;
}

/* ============================================
   NEW: Attendance
   ============================================ */

export type AttendanceStatus = "present" | "absent" | "late" | "excused";

export interface AttendanceRecord {
  id: string;
  courseId: string;
  studentId: string;
  date: string; // YYYY-MM-DD
  status: AttendanceStatus;
  markedBy: string;
  notes: string;
  createdAt: string;
}

/* ============================================
   NEW: Teacher Notes (book + course code)
   ============================================ */

export interface TeacherNote {
  id: string;
  courseId: string;
  bookName: string;
  courseCode: string;
  title: string;
  content: string;
  authorId: string;
  createdAt: string;
  updatedAt: string;
}

/* ============================================
   NEW: Student Department Enrollment
   ============================================ */

export interface StudentDepartment {
  id: string;
  studentId: string;
  departmentId: string;
  enrolledAt: string;
  enrolledBy: string;
}

/* ============================================
   NEW: Excel Import/Export payloads
   ============================================ */

export interface StudentImportRow {
  name: string;
  rollNumber: string;
  contact: string;
  courseId?: string;
  departmentId?: string;
}

export interface StudentImportResult {
  imported: number;
  errors: { row: number; message: string }[];
}

/* ============================================
   Admin console (/api/v1/admin/*, admin role only)
   ============================================ */

/** A user as the admin console sees it. Never includes the password hash. */
export interface AdminUser {
  id: string;
  displayName: string;
  email: string;
  phone: string;
  role: Role;
  isActive: boolean;
  isPhoneVerified: boolean;
  courseIds: string[];
  createdAt: string;
}

/** Body of POST /admin/users. One of email or phone is required. */
export interface AdminUserCreate {
  displayName: string;
  email?: string;
  phone?: string;
  role: Role;
  /** At least 8 characters. */
  password: string;
}

/** Body of PATCH /admin/users/:id. Every field is optional. */
export interface AdminUserUpdate {
  displayName?: string;
  email?: string;
  phone?: string;
  role?: Role;
  isActive?: boolean;
}

export interface AdminCourse {
  id: string;
  title: string;
  code: string;
  term: string;
  teacherId: string;
  teacherName: string;
  studentIds: string[];
  studentCount: number;
  assignmentCount: number;
  createdAt: string;
}

/** Body of POST /admin/courses; PATCH /admin/courses/:id takes any subset. */
export interface AdminCourseCreate {
  title: string;
  code: string;
  term: string;
  teacherId: string;
}

/** One row per student + assignment that has an effort score. */
export interface IntegrityRow {
  studentId: string;
  studentName: string;
  assignmentId: string;
  assignmentTitle: string;
  courseId: string;
  courseTitle: string;
  score: number;
  flags: IntegrityFlag[];
  computedAt: string;
}

/** GET /admin/overview. */
export interface Overview {
  counts: {
    students: number;
    teachers: number;
    admins: number;
    inactiveUsers: number;
    courses: number;
    departments: number;
    assignments: number;
    submissions: number;
    telemetryBatches: number;
    /** Rows of GET /admin/integrity?flagged=true. */
    flaggedReports: number;
  };
  storage: "memory" | "postgres";
  database: "ok" | "unreachable";
  schemaVersion: number | null;
  version: string;
  serverTime: string;
}

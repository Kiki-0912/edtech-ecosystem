// Admin console API (/api/v1/admin) on the seeded in-memory store.
// Tests run in file order and share one app; each describe leaves the seed data
// usable for the ones after it.
import crypto from "node:crypto";
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import Fastify from "fastify";
import type { FastifyInstance, LightMyRequestResponse } from "fastify";
import type { AdminCourse, AdminUser, IntegrityRow, Overview } from "@edtech/shared";
import { config } from "../src/config";
import { buildApp } from "../src/create-app";
import adminRoutes from "../src/routes/admin";
import { MIGRATIONS } from "../src/store/migrations";
import * as store from "../src/store/db";

// Seeded accounts (apps/api/src/store/memory.ts); password123 for all.
const PASSWORD = "password123";
const ADMIN = "+15550001005"; // u-admin-1
const TEACHER = "+15550001001"; // u-teacher-1, teaches c-001
const STUDENT_2 = "+15550001003"; // u-student-2
const STUDENT_3 = "+15550001004"; // u-student-3
const STUDENT_4 = "+15550001006"; // u-student-4

const ADMIN_USER_KEYS = [
  "courseIds",
  "createdAt",
  "displayName",
  "email",
  "id",
  "isActive",
  "isPhoneVerified",
  "phone",
  "role",
];
const ADMIN_COURSE_KEYS = [
  "assignmentCount",
  "code",
  "createdAt",
  "id",
  "studentCount",
  "studentIds",
  "teacherId",
  "teacherName",
  "term",
  "title",
];

type Method = "GET" | "HEAD" | "POST" | "PATCH" | "PUT" | "DELETE";
type Headers = { authorization: string };

let app: FastifyInstance;
const headers: Record<string, Headers> = {};
let phoneCounter = 0;

const nextPhone = () => `+1555990${String(++phoneCounter).padStart(4, "0")}`;

const login = (payload: Record<string, string>) =>
  app.inject({ method: "POST", url: "/api/v1/auth/login", payload });

async function signIn(phone: string, password = PASSWORD): Promise<Headers> {
  const res = await login({ phone, password });
  assert.equal(res.statusCode, 200, res.body);
  return { authorization: `Bearer ${res.json().data.token}` };
}

/** Call an admin route (as the seeded admin unless `as` is given). */
const admin = (method: Method, path: string, payload?: object, as: Headers = headers.admin) =>
  app.inject({ method, url: `/api/v1/admin${path}`, headers: as, payload });

function expectError(res: LightMyRequestResponse, status: number, code: string) {
  assert.equal(res.statusCode, status, res.body);
  assert.equal(res.json().error.code, code, res.body);
}

async function createUser(fields: Record<string, unknown> = {}): Promise<AdminUser> {
  const res = await admin("POST", "/users", {
    displayName: "Created User",
    phone: nextPhone(),
    role: "student",
    password: "created-pass-1",
    ...fields,
  });
  assert.equal(res.statusCode, 201, res.body);
  return res.json().data;
}

async function listUsers(query = ""): Promise<AdminUser[]> {
  const res = await admin("GET", `/users${query}`);
  assert.equal(res.statusCode, 200, res.body);
  return res.json().data;
}

async function findUser(id: string): Promise<AdminUser | undefined> {
  return (await listUsers()).find((user) => user.id === id);
}

async function listCourses(): Promise<AdminCourse[]> {
  const res = await admin("GET", "/courses");
  assert.equal(res.statusCode, 200, res.body);
  return res.json().data;
}

async function integrityRows(query = ""): Promise<IntegrityRow[]> {
  const res = await admin("GET", `/integrity${query}`);
  assert.equal(res.statusCode, 200, res.body);
  return res.json().data;
}

/** Upload a telemetry batch signed the way the extension signs it. */
async function uploadTelemetry(
  as: Headers,
  studentId: string,
  assignmentId: string,
  type: "paste" | "keystroke",
) {
  const key = crypto.randomBytes(32);
  const batch = {
    batchId: `b-${crypto.randomUUID()}`,
    studentId,
    assignmentId,
    createdAt: new Date().toISOString(),
    events: [
      {
        id: crypto.randomUUID(),
        sessionId: `s-${crypto.randomUUID()}`,
        assignmentId,
        studentId,
        type,
        occurredAt: new Date().toISOString(),
        payload: type === "paste" ? { characterCount: 900 } : { deltaMs: 200 },
      },
    ],
  };
  const res = await app.inject({
    method: "POST",
    url: "/api/v1/telemetry/batches",
    headers: as,
    payload: {
      ...batch,
      clientSignature: crypto
        .createHmac("sha256", key)
        .update(JSON.stringify(batch))
        .digest("base64url"),
      clientPublicKey: JSON.stringify({ kty: "oct", k: key.toString("base64url") }),
    },
  });
  assert.equal(res.statusCode, 202, res.body);
}

/** Every route the admin module defines, read from the module itself. */
async function adminRouteTable(): Promise<{ method: string; url: string }[]> {
  const probe = Fastify();
  const routes: { method: string; url: string }[] = [];
  probe.addHook("onRoute", (route) => {
    for (const method of [route.method].flat()) routes.push({ method, url: route.url });
  });
  await probe.register(adminRoutes, { prefix: "/api/v1/admin" });
  await probe.ready();
  await probe.close();
  return routes;
}

before(async () => {
  app = await buildApp();
  headers.admin = await signIn(ADMIN);
  headers.teacher = await signIn(TEACHER);
  headers.student = await signIn(STUDENT_4);
  headers.student2 = await signIn(STUDENT_2);
  headers.student3 = await signIn(STUDENT_3);
});

after(async () => {
  await app.close();
});

describe("admin guard", () => {
  test("every admin route and method rejects anonymous, student and teacher callers", async () => {
    const routes = await adminRouteTable();
    assert.deepEqual(
      routes
        .filter((route) => route.method !== "HEAD")
        .map((route) => `${route.method} ${route.url}`)
        .sort(),
      [
        "DELETE /api/v1/admin/courses/:id",
        "DELETE /api/v1/admin/users/:id",
        "GET /api/v1/admin/courses",
        "GET /api/v1/admin/integrity",
        "GET /api/v1/admin/overview",
        "GET /api/v1/admin/users",
        "PATCH /api/v1/admin/courses/:id",
        "PATCH /api/v1/admin/users/:id",
        "POST /api/v1/admin/courses",
        "POST /api/v1/admin/users",
        "POST /api/v1/admin/users/:id/password",
        "PUT /api/v1/admin/courses/:id/students",
      ],
      "update this list (and the dashboard) when adding an admin route",
    );

    for (const { method, url: pattern } of routes) {
      // Ids that don't exist: a 403 here can only come from the guard.
      const url = pattern.replace(/:\w+/g, "guard-probe");
      const payload = ["POST", "PATCH", "PUT"].includes(method) ? {} : undefined;
      const call = (as?: Headers) =>
        app.inject({ method: method as Method, url, headers: as, payload });
      const label = `${method} ${url}`;

      const anonymous = await call();
      assert.equal(anonymous.statusCode, 401, label);
      if (method !== "HEAD") assert.equal(anonymous.json().error.code, "UNAUTHORIZED", label);

      for (const who of ["student", "teacher"]) {
        const res = await call(headers[who]);
        assert.equal(res.statusCode, 403, `${who}: ${label}`);
        if (method !== "HEAD") assert.equal(res.json().error.code, "FORBIDDEN", `${who}: ${label}`);
      }

      const asAdmin = await call(headers.admin);
      assert.ok(![401, 403].includes(asAdmin.statusCode), `admin: ${label} ${asAdmin.body}`);
    }
  });
});

describe("public sign-up", () => {
  for (const role of ["teacher", "admin"]) {
    test(`cannot create a ${role}`, async () => {
      const res = await app.inject({
        method: "POST",
        url: "/api/v1/auth/register",
        payload: { phone: nextPhone(), password: "secret123", role },
      });
      expectError(res, 400, "INVALID_BODY");
      assert.equal(
        res.json().error.message,
        "Public sign-up creates student accounts; teachers are added by an admin",
      );
    });
  }

  test("creates students", async () => {
    for (const payload of [{}, { role: "student" }]) {
      const res = await app.inject({
        method: "POST",
        url: "/api/v1/auth/register",
        payload: { phone: nextPhone(), password: "secret123", ...payload },
      });
      assert.equal(res.statusCode, 201, res.body);
      assert.equal(res.json().data.user.role, "student");
    }
  });
});

describe("users", () => {
  test("the list has every user, without password hashes", async () => {
    const users = await listUsers();
    for (const id of ["u-teacher-1", "u-student-1", "u-student-4", "u-admin-1"]) {
      assert.ok(users.some((user) => user.id === id), id);
    }
    for (const user of users) {
      assert.deepEqual(Object.keys(user).sort(), ADMIN_USER_KEYS, user.id);
    }
    const seededAdmin = users.find((user) => user.id === "u-admin-1")!;
    assert.equal(seededAdmin.isActive, true);
    assert.equal(seededAdmin.isPhoneVerified, true);
    assert.deepEqual(seededAdmin.courseIds, []);
  });

  test("filters by role, search text and status", async () => {
    const ids = (users: AdminUser[]) => users.map((user) => user.id);
    assert.deepEqual(ids(await listUsers("?role=teacher")), ["u-teacher-1"]);
    assert.deepEqual(ids(await listUsers("?q=SAMEER")), ["u-student-2"]);
    assert.deepEqual(ids(await listUsers("?q=Usman.Shahid%40")), ["u-admin-1"]);
    assert.deepEqual(ids(await listUsers("?q=0001004")), ["u-student-3"]);
    assert.deepEqual(ids(await listUsers("?role=teacher&q=sameer")), []);
    assert.deepEqual(await listUsers("?status=inactive"), []);
    assert.equal((await listUsers("?status=active")).length, (await listUsers()).length);
    assert.equal((await listUsers("?role=&q=&status=")).length, (await listUsers()).length);

    expectError(await admin("GET", "/users?role=janitor"), 400, "INVALID_QUERY");
    expectError(await admin("GET", "/users?status=gone"), 400, "INVALID_QUERY");
  });

  test("an admin creates any role, and the account can sign in", async () => {
    const phone = nextPhone();
    const res = await admin("POST", "/users", {
      displayName: "  New Teacher  ",
      email: "new.teacher@example.edu",
      phone,
      role: "teacher",
      password: "teacher-pass-1",
    });
    assert.equal(res.statusCode, 201, res.body);
    const user: AdminUser = res.json().data;
    assert.deepEqual(Object.keys(user).sort(), ADMIN_USER_KEYS);
    assert.equal(user.displayName, "New Teacher");
    assert.equal(user.role, "teacher");
    assert.equal(user.isActive, true);
    assert.equal(user.isPhoneVerified, false);
    assert.deepEqual(user.courseIds, []);
    assert.ok(!Number.isNaN(Date.parse(user.createdAt)));

    const signedIn = await login({ email: "new.teacher@example.edu", password: "teacher-pass-1" });
    assert.equal(signedIn.statusCode, 200, signedIn.body);
    assert.equal(signedIn.json().data.user.role, "teacher");
    assert.equal(signedIn.json().data.user.passwordHash, undefined);

    const emailOnly = await createUser({ phone: undefined, email: "email.only@example.edu" });
    assert.equal(emailOnly.phone, "");
    const anotherAdmin = await createUser({ role: "admin" });
    assert.equal(anotherAdmin.role, "admin");
    // Clean up: later tests rely on u-admin-1 being the only admin.
    assert.equal((await admin("DELETE", `/users/${anotherAdmin.id}`)).statusCode, 200);
  });

  test("create rejects invalid bodies and duplicates", async () => {
    const valid = { displayName: "X", phone: nextPhone(), role: "student", password: "long-enough" };
    const invalid: Record<string, unknown>[] = [
      { ...valid, displayName: undefined },
      { ...valid, displayName: "   " },
      { ...valid, phone: undefined },
      { ...valid, phone: "", email: "" },
      { ...valid, phone: 15550000000 },
      { ...valid, role: undefined },
      { ...valid, role: "superuser" },
      { ...valid, password: undefined },
      { ...valid, password: "1234567" },
    ];
    for (const payload of invalid) {
      expectError(await admin("POST", "/users", payload), 400, "INVALID_BODY");
    }
    expectError(await admin("POST", "/users", undefined), 400, "INVALID_BODY");

    expectError(
      await admin("POST", "/users", { ...valid, phone: "", email: "tayyab@example.edu" }),
      409,
      "USER_EXISTS",
    );
    expectError(await admin("POST", "/users", { ...valid, phone: TEACHER }), 409, "USER_EXISTS");
  });

  test("patch updates fields and rejects conflicts and bad values", async () => {
    expectError(await admin("PATCH", "/users/nobody", { displayName: "X" }), 404, "USER_NOT_FOUND");

    const user = await createUser();
    const res = await admin("PATCH", `/users/${user.id}`, {
      displayName: "Renamed",
      email: "renamed@example.edu",
    });
    assert.equal(res.statusCode, 200, res.body);
    assert.equal(res.json().data.displayName, "Renamed");
    assert.equal(res.json().data.email, "renamed@example.edu");
    assert.equal(res.json().data.phone, user.phone);

    // Re-sending its own values is not a conflict.
    const same = await admin("PATCH", `/users/${user.id}`, { email: "renamed@example.edu" });
    assert.equal(same.statusCode, 200, same.body);
    assert.equal((await admin("PATCH", `/users/${user.id}`, {})).statusCode, 200);

    const patch = (payload: object) => admin("PATCH", `/users/${user.id}`, payload);
    expectError(await patch({ email: "tayyab@example.edu" }), 409, "USER_EXISTS");
    expectError(await patch({ phone: TEACHER }), 409, "USER_EXISTS");
    expectError(await patch({ role: "owner" }), 400, "INVALID_BODY");
    expectError(await patch({ isActive: "no" }), 400, "INVALID_BODY");
    expectError(await patch({ displayName: "" }), 400, "INVALID_BODY");
    expectError(await patch({ email: "", phone: "" }), 400, "INVALID_BODY");
  });

  test("a teacher assigned to a course keeps the teacher role", async () => {
    expectError(
      await admin("PATCH", "/users/u-teacher-1", { role: "student" }),
      409,
      "USER_IN_USE",
    );
  });

  test("a student who becomes staff leaves every course roster", async () => {
    const user = await createUser();
    const course = (await listCourses()).find((entry) => entry.id === "c-001")!;
    const roster = await admin("PUT", "/courses/c-001/students", {
      studentIds: [...course.studentIds, user.id],
    });
    assert.equal(roster.statusCode, 200, roster.body);
    assert.deepEqual((await findUser(user.id))!.courseIds, ["c-001"]);

    const res = await admin("PATCH", `/users/${user.id}`, { role: "teacher" });
    assert.equal(res.statusCode, 200, res.body);
    assert.equal(res.json().data.role, "teacher");
    assert.deepEqual(res.json().data.courseIds, []);
    const after = (await listCourses()).find((entry) => entry.id === "c-001")!;
    assert.deepEqual(after.studentIds, course.studentIds);
    assert.ok(!(await store.getChannel("ch-002"))!.memberIds.includes(user.id));
  });
});

describe("self and last-admin protection", () => {
  test("the only active admin cannot demote, disable or delete themself", async () => {
    // CANNOT_MODIFY_SELF wins over LAST_ADMIN, whatever the number of admins.
    expectError(
      await admin("PATCH", "/users/u-admin-1", { role: "teacher" }),
      409,
      "CANNOT_MODIFY_SELF",
    );
    expectError(
      await admin("PATCH", "/users/u-admin-1", { isActive: false }),
      409,
      "CANNOT_MODIFY_SELF",
    );
    expectError(await admin("DELETE", "/users/u-admin-1"), 409, "CANNOT_MODIFY_SELF");
    assert.equal((await findUser("u-admin-1"))!.role, "admin");
  });

  test("the store refuses to remove the last active admin", async () => {
    assert.equal(await store.updateUser("u-admin-1", { role: "teacher" }), "last_admin");
    assert.equal(await store.updateUser("u-admin-1", { isActive: false }), "last_admin");
    assert.equal(await store.deleteUser("u-admin-1"), "last_admin");
    // Other changes to the last admin still go through.
    assert.equal(await store.updateUser("u-admin-1", { role: "admin", isActive: true }), "updated");
    const user = (await findUser("u-admin-1"))!;
    assert.equal(user.role, "admin");
    assert.equal(user.isActive, true);
  });

  const removals: [string, (id: string) => [Method, string, object?]][] = [
    ["delete", (id) => ["DELETE", `/users/${id}`]],
    ["demote", (id) => ["PATCH", `/users/${id}`, { role: "teacher" }]],
    ["deactivate", (id) => ["PATCH", `/users/${id}`, { isActive: false }]],
  ];
  for (const [label, removal] of removals) {
    test(`two admins who ${label} each other at once leave one active admin`, async () => {
      const makeAdmin = async () => {
        const phone = nextPhone();
        const user = await createUser({ role: "admin", phone, password: "race-admin-1" });
        return { id: user.id, headers: await signIn(phone, "race-admin-1") };
      };
      const b = await makeAdmin();
      const c = await makeAdmin();
      // Leave b and c as the only active admins.
      assert.equal(await store.updateUser("u-admin-1", { isActive: false }), "updated");
      try {
        const remove = (target: string, as: Headers) => {
          const [method, path, payload] = removal(target);
          return admin(method, path, payload, as);
        };
        const results = await Promise.all([remove(c.id, b.headers), remove(b.id, c.headers)]);
        const body = results.map((res) => res.body).join("\n");
        // One wins. The other is refused by the store's last-admin guard or, if
        // it reaches authentication after the winner's write, as a caller who
        // just lost admin rights (revoked token or deleted account).
        assert.equal(results.filter((res) => res.statusCode === 200).length, 1, body);
        const loser = results.find((res) => res.statusCode !== 200)!;
        assert.ok(
          (loser.statusCode === 409 && loser.json().error.code === "LAST_ADMIN") ||
            loser.statusCode === 401,
          body,
        );
        const activeAdmins = (await store.getUsers()).filter(
          (user) => user.role === "admin" && user.isActive !== false,
        );
        assert.equal(activeAdmins.length, 1, body);
      } finally {
        assert.equal(await store.updateUser("u-admin-1", { isActive: true }), "updated");
        for (const id of [b.id, c.id]) await store.deleteUser(id);
        // Deactivating u-admin-1 revoked its token.
        headers.admin = await signIn(ADMIN);
      }
    });
  }

  test("concurrent store writes cannot remove both of the last two active admins", async () => {
    const b = await createUser({ role: "admin" });
    const c = await createUser({ role: "admin" });
    assert.equal(await store.updateUser("u-admin-1", { isActive: false }), "updated");
    try {
      const results = await Promise.all([
        store.updateUser(b.id, { role: "teacher" }),
        store.updateUser(c.id, { isActive: false }),
      ]);
      assert.deepEqual([...results].sort(), ["last_admin", "updated"]);
      const remaining = results[0] === "last_admin" ? b.id : c.id;
      assert.equal(await store.deleteUser(remaining), "last_admin");
    } finally {
      assert.equal(await store.updateUser("u-admin-1", { isActive: true }), "updated");
      for (const id of [b.id, c.id]) await store.deleteUser(id);
      headers.admin = await signIn(ADMIN);
    }
  });

  test("admins can edit their own profile", async () => {
    const res = await admin("PATCH", "/users/u-admin-1", {
      displayName: "Usman S.",
      role: "admin",
      isActive: true,
    });
    assert.equal(res.statusCode, 200, res.body);
    assert.equal(res.json().data.displayName, "Usman S.");
    await admin("PATCH", "/users/u-admin-1", { displayName: "Usman Shahid" });
  });

  test("with another admin, self changes are still refused; the other admin is not", async () => {
    const phone = nextPhone();
    const second = await createUser({ role: "admin", phone, password: "second-admin-1" });

    expectError(
      await admin("PATCH", "/users/u-admin-1", { role: "student" }),
      409,
      "CANNOT_MODIFY_SELF",
    );
    expectError(
      await admin("PATCH", "/users/u-admin-1", { isActive: false }),
      409,
      "CANNOT_MODIFY_SELF",
    );
    expectError(await admin("DELETE", "/users/u-admin-1"), 409, "CANNOT_MODIFY_SELF");

    // The second admin can be disabled, demoted and deleted by the first.
    const disabled = await admin("PATCH", `/users/${second.id}`, { isActive: false });
    assert.equal(disabled.statusCode, 200, disabled.body);
    expectError(await login({ phone, password: "second-admin-1" }), 403, "ACCOUNT_DISABLED");
    const demoted = await admin("PATCH", `/users/${second.id}`, { role: "teacher" });
    assert.equal(demoted.statusCode, 200, demoted.body);
    assert.equal((await admin("DELETE", `/users/${second.id}`)).statusCode, 200);
    assert.equal(await findUser(second.id), undefined);
  });
});

describe("disabled accounts", () => {
  test("cannot sign in, and their existing tokens stay revoked after re-enabling", async () => {
    const phone = nextPhone();
    const user = await createUser({ phone, password: "student-pass-1" });
    const token = await signIn(phone, "student-pass-1");

    const disabled = await admin("PATCH", `/users/${user.id}`, { isActive: false });
    assert.equal(disabled.statusCode, 200, disabled.body);
    assert.equal(disabled.json().data.isActive, false);
    assert.deepEqual(
      (await listUsers("?status=inactive")).map((entry) => entry.id),
      [user.id],
    );
    assert.ok(!(await listUsers("?status=active")).some((entry) => entry.id === user.id));

    expectError(await login({ phone, password: "student-pass-1" }), 403, "ACCOUNT_DISABLED");
    const courses = await app.inject({ method: "GET", url: "/api/v1/courses", headers: token });
    expectError(courses, 401, "ACCOUNT_DISABLED");
    const me = await app.inject({ method: "GET", url: "/api/v1/auth/me", headers: token });
    assert.equal(me.statusCode, 401, me.body);

    process.env.SMS_DEV_ECHO = "true";
    try {
      const sent = await app.inject({
        method: "POST",
        url: "/api/v1/auth/send-sms",
        payload: { phone },
      });
      assert.equal(sent.statusCode, 200, sent.body);
      const verify = await app.inject({
        method: "POST",
        url: "/api/v1/auth/verify-sms",
        payload: { phone, code: sent.json().data.code },
      });
      expectError(verify, 403, "ACCOUNT_DISABLED");
    } finally {
      delete process.env.SMS_DEV_ECHO;
    }

    const enabled = await admin("PATCH", `/users/${user.id}`, { isActive: true });
    assert.equal(enabled.json().data.isActive, true);
    // Re-enabling does not bring back tokens issued before the deactivation
    // (they may be a stolen session the deactivation was meant to cut off).
    const again = await app.inject({ method: "GET", url: "/api/v1/courses", headers: token });
    expectError(again, 401, "SESSION_REVOKED");
    expectError(
      await app.inject({ method: "GET", url: "/api/v1/auth/me", headers: token }),
      401,
      "SESSION_REVOKED",
    );
    const fresh = await signIn(phone, "student-pass-1");
    const courses2 = await app.inject({ method: "GET", url: "/api/v1/courses", headers: fresh });
    assert.equal(courses2.statusCode, 200, courses2.body);
  });
});

describe("token revocation", () => {
  const get = (url: string, as: Headers) => app.inject({ method: "GET", url, headers: as });

  test("a password reset revokes the user's existing tokens, including an admin's", async () => {
    const phone = nextPhone();
    const user = await createUser({ role: "admin", phone, password: "stolen-admin-1" });
    const stolen = await signIn(phone, "stolen-admin-1");
    assert.equal((await get("/api/v1/admin/overview", stolen)).statusCode, 200);

    const reset = await admin("POST", `/users/${user.id}/password`, { password: "recovered-1" });
    assert.equal(reset.statusCode, 200, reset.body);
    expectError(await get("/api/v1/admin/overview", stolen), 401, "SESSION_REVOKED");
    expectError(await get("/api/v1/auth/me", stolen), 401, "SESSION_REVOKED");
    const backdoor = { displayName: "Backdoor", phone: nextPhone(), role: "admin" };
    expectError(
      await admin("POST", "/users", { ...backdoor, password: "backdoor-1" }, stolen),
      401,
      "SESSION_REVOKED",
    );

    const fresh = await signIn(phone, "recovered-1");
    assert.equal((await get("/api/v1/admin/overview", fresh)).statusCode, 200);
    assert.equal((await admin("DELETE", `/users/${user.id}`)).statusCode, 200);
  });

  test("a role change revokes tokens; profile edits do not", async () => {
    const phone = nextPhone();
    const user = await createUser({ role: "admin", phone, password: "demoted-admin-1" });
    const token = await signIn(phone, "demoted-admin-1");

    const renamed = await admin("PATCH", `/users/${user.id}`, {
      displayName: "Renamed",
      role: "admin",
    });
    assert.equal(renamed.statusCode, 200, renamed.body);
    assert.equal((await get("/api/v1/admin/overview", token)).statusCode, 200);

    const demoted = await admin("PATCH", `/users/${user.id}`, { role: "teacher" });
    assert.equal(demoted.statusCode, 200, demoted.body);
    expectError(await get("/api/v1/admin/overview", token), 401, "SESSION_REVOKED");
    assert.equal((await admin("DELETE", `/users/${user.id}`)).statusCode, 200);
  });

  test("tokens without a version (issued before versions existed) are version 0", async () => {
    const phone = nextPhone();
    const user = await createUser({ phone, password: "legacy-token-1" });
    const legacy = (sub: string) => {
      const now = Math.floor(Date.now() / 1000);
      const body = Buffer.from(JSON.stringify({ sub, iat: now, exp: now + 60 })).toString(
        "base64url",
      );
      const signature = crypto
        .createHmac("sha256", config.authSecret)
        .update(body)
        .digest("base64url");
      return { authorization: `Bearer ${body}.${signature}` };
    };
    assert.equal((await get("/api/v1/auth/me", legacy(user.id))).statusCode, 200);

    await admin("POST", `/users/${user.id}/password`, { password: "legacy-token-2" });
    expectError(await get("/api/v1/auth/me", legacy(user.id)), 401, "SESSION_REVOKED");
  });
});

describe("password reset", () => {
  test("sets a new password", async () => {
    const phone = nextPhone();
    const user = await createUser({ phone, password: "old-password-1" });

    expectError(
      await admin("POST", `/users/${user.id}/password`, { password: "short" }),
      400,
      "INVALID_BODY",
    );
    expectError(await admin("POST", `/users/${user.id}/password`, {}), 400, "INVALID_BODY");
    expectError(
      await admin("POST", "/users/nobody/password", { password: "new-password-1" }),
      404,
      "USER_NOT_FOUND",
    );

    const res = await admin("POST", `/users/${user.id}/password`, { password: "new-password-1" });
    assert.equal(res.statusCode, 200, res.body);
    assert.deepEqual(res.json(), { data: { success: true } });
    assert.equal((await login({ phone, password: "new-password-1" })).statusCode, 200);
    expectError(await login({ phone, password: "old-password-1" }), 401, "INVALID_CREDENTIALS");
  });
});

describe("courses and rosters", () => {
  let created: AdminCourse;
  let otherTeacher: AdminUser;

  test("lists courses with teacher name and counts", async () => {
    const course = (await listCourses()).find((entry) => entry.id === "c-001")!;
    assert.deepEqual(Object.keys(course).sort(), ADMIN_COURSE_KEYS);
    assert.equal(course.teacherId, "u-teacher-1");
    assert.equal(course.teacherName, "Tayyab");
    assert.equal(course.studentCount, course.studentIds.length);
    assert.equal(course.studentCount, 4);
    assert.equal(course.assignmentCount, 4);
  });

  test("create validates the body and the teacher", async () => {
    const valid = { title: "Databases", code: "CS 220", term: "Spring 2027", teacherId: "u-teacher-1" };
    for (const field of ["title", "code", "term", "teacherId"]) {
      expectError(
        await admin("POST", "/courses", { ...valid, [field]: " " }),
        400,
        "INVALID_BODY",
      );
    }
    for (const teacherId of ["u-student-1", "u-admin-1", "nobody"]) {
      expectError(await admin("POST", "/courses", { ...valid, teacherId }), 400, "INVALID_TEACHER");
    }

    const res = await admin("POST", "/courses", valid);
    assert.equal(res.statusCode, 201, res.body);
    created = res.json().data;
    assert.deepEqual(Object.keys(created).sort(), ADMIN_COURSE_KEYS);
    assert.equal(created.teacherName, "Tayyab");
    assert.deepEqual(created.studentIds, []);
    assert.equal(created.studentCount, 0);
    assert.equal(created.assignmentCount, 0);
    assert.ok((await findUser("u-teacher-1"))!.courseIds.includes(created.id));

    const visible = await app.inject({ method: "GET", url: "/api/v1/courses", headers: headers.teacher });
    assert.ok(visible.json().data.some((course: { id: string }) => course.id === created.id));
  });

  test("patch updates fields and reassigns the teacher", async () => {
    expectError(await admin("PATCH", "/courses/nope", { title: "X" }), 404, "COURSE_NOT_FOUND");
    expectError(
      await admin("PATCH", `/courses/${created.id}`, { teacherId: "u-student-1" }),
      400,
      "INVALID_TEACHER",
    );
    expectError(await admin("PATCH", `/courses/${created.id}`, { title: "" }), 400, "INVALID_BODY");

    otherTeacher = await createUser({ role: "teacher", displayName: "Second Teacher" });
    const res = await admin("PATCH", `/courses/${created.id}`, {
      title: "Database Systems",
      teacherId: otherTeacher.id,
    });
    assert.equal(res.statusCode, 200, res.body);
    assert.equal(res.json().data.title, "Database Systems");
    assert.equal(res.json().data.code, "CS 220");
    assert.equal(res.json().data.teacherName, "Second Teacher");
    assert.ok(!(await findUser("u-teacher-1"))!.courseIds.includes(created.id));
    assert.deepEqual((await findUser(otherTeacher.id))!.courseIds, [created.id]);
  });

  test("a new teacher replaces the old one in the course chat channels", async () => {
    const move = (teacherId: string) => admin("PATCH", "/courses/c-001", { teacherId });
    assert.equal((await move(otherTeacher.id)).statusCode, 200);
    let members = (await store.getChannel("ch-001"))!.memberIds;
    assert.ok(members.includes(otherTeacher.id) && !members.includes("u-teacher-1"));

    assert.equal((await move("u-teacher-1")).statusCode, 200);
    members = (await store.getChannel("ch-001"))!.memberIds;
    assert.ok(!members.includes(otherTeacher.id) && members.includes("u-teacher-1"));
    assert.ok((await findUser("u-teacher-1"))!.courseIds.includes("c-001"));
  });

  test("put students validates every id", async () => {
    const put = (id: string, payload: object) => admin("PUT", `/courses/${id}/students`, payload);
    expectError(await put("nope", { studentIds: [] }), 404, "COURSE_NOT_FOUND");
    expectError(await put(created.id, {}), 400, "INVALID_BODY");
    expectError(await put(created.id, { studentIds: "u-student-1" }), 400, "INVALID_BODY");
    expectError(await put(created.id, { studentIds: [42] }), 400, "INVALID_BODY");
    for (const bad of ["u-teacher-1", "u-admin-1", "nobody"]) {
      expectError(
        await put(created.id, { studentIds: ["u-student-1", bad] }),
        400,
        "INVALID_STUDENT",
      );
    }
    assert.deepEqual((await listCourses()).find((c) => c.id === created.id)!.studentIds, []);
  });

  test("put students replaces the roster and keeps courseIds in sync", async () => {
    const put = (studentIds: string[]) =>
      admin("PUT", `/courses/${created.id}/students`, { studentIds });

    const first = await put(["u-student-2", "u-student-3", "u-student-2"]);
    assert.equal(first.statusCode, 200, first.body);
    assert.deepEqual(first.json().data.studentIds, ["u-student-2", "u-student-3"]);
    assert.equal(first.json().data.studentCount, 2);
    assert.deepEqual((await findUser("u-student-2"))!.courseIds, ["c-001", created.id]);

    const second = await put(["u-student-3"]);
    assert.deepEqual(second.json().data.studentIds, ["u-student-3"]);
    assert.deepEqual((await findUser("u-student-2"))!.courseIds, ["c-001"]);
    assert.deepEqual((await findUser("u-student-3"))!.courseIds, ["c-001", created.id]);
  });

  test("roster changes add and remove students in the course chat channels", async () => {
    const roster = (await listCourses()).find((c) => c.id === "c-001")!.studentIds;
    const removed = await admin("PUT", "/courses/c-001/students", {
      studentIds: roster.filter((id) => id !== "u-student-3"),
    });
    assert.equal(removed.statusCode, 200, removed.body);
    assert.ok(!(await store.getChannel("ch-001"))!.memberIds.includes("u-student-3"));
    assert.ok(!(await findUser("u-student-3"))!.courseIds.includes("c-001"));

    const restored = await admin("PUT", "/courses/c-001/students", { studentIds: roster });
    assert.deepEqual(restored.json().data.studentIds, roster);
    assert.ok((await store.getChannel("ch-001"))!.memberIds.includes("u-student-3"));
    assert.ok((await findUser("u-student-3"))!.courseIds.includes("c-001"));
  });
});

describe("integrity", () => {
  test("lists one row per student and assignment, newest first, with a flagged filter", async () => {
    await uploadTelemetry(headers.student3, "u-student-3", "a-002", "keystroke");
    await new Promise((resolve) => setTimeout(resolve, 5));
    await uploadTelemetry(headers.student2, "u-student-2", "a-001", "paste");
    // A second session for the same pair is still one row.
    await uploadTelemetry(headers.student2, "u-student-2", "a-001", "paste");

    const rows = await integrityRows();
    assert.equal(rows.length, 2);
    const sorted = [...rows].sort((a, b) => b.computedAt.localeCompare(a.computedAt));
    assert.deepEqual(rows, sorted);

    const pasted = rows[0];
    assert.equal(pasted.studentId, "u-student-2");
    assert.equal(pasted.studentName, "Sameer");
    assert.equal(pasted.assignmentId, "a-001");
    assert.equal(pasted.assignmentTitle, "Usability Study Report");
    assert.equal(pasted.courseId, "c-001");
    assert.equal(pasted.courseTitle, "Human-Computer Interaction");
    assert.ok(pasted.flags.includes("large_paste"), pasted.flags.join());
    // Same score as the per-student integrity report.
    const report = await app.inject({
      method: "GET",
      url: "/api/v1/integrity/a-001/u-student-2",
      headers: headers.admin,
    });
    assert.equal(pasted.score, report.json().data.effortScore.score);
    assert.equal(pasted.computedAt, report.json().data.effortScore.computedAt);

    assert.deepEqual(rows[1].flags, ["none"]);
    assert.equal(rows[1].studentId, "u-student-3");

    const flaggedRows = await integrityRows("?flagged=true");
    assert.deepEqual(
      flaggedRows.map((row) => `${row.studentId}/${row.assignmentId}`),
      ["u-student-2/a-001"],
    );
    assert.deepEqual(await integrityRows("?flagged=false"), rows);
    expectError(await admin("GET", "/integrity?flagged=maybe"), 400, "INVALID_QUERY");
  });
});

describe("overview", () => {
  test("counts match the data and the system fields are filled in", async () => {
    const inactive = await createUser();
    await admin("PATCH", `/users/${inactive.id}`, { isActive: false });

    const res = await admin("GET", "/overview");
    assert.equal(res.statusCode, 200, res.body);
    const overview: Overview = res.json().data;

    const users = await listUsers();
    const courses = await listCourses();
    const byRole = (role: string) => users.filter((user) => user.role === role).length;
    let submissions = 0;
    for (const course of courses) {
      for (const assignment of await store.getAssignmentsByCourse(course.id)) {
        submissions += (await store.getSubmissionsByAssignment(assignment.id)).length;
      }
    }
    assert.deepEqual(overview.counts, {
      students: byRole("student"),
      teachers: byRole("teacher"),
      admins: byRole("admin"),
      inactiveUsers: (await listUsers("?status=inactive")).length,
      courses: courses.length,
      departments: 18,
      assignments: courses.reduce((sum, course) => sum + course.assignmentCount, 0),
      submissions,
      telemetryBatches: (await store.getTelemetryBatches()).length,
      flaggedReports: (await integrityRows("?flagged=true")).length,
    });
    assert.equal(overview.counts.inactiveUsers, 1);
    assert.equal(overview.counts.admins, 1);
    assert.equal(overview.counts.telemetryBatches, 3);
    assert.equal(overview.counts.flaggedReports, 1);

    assert.equal(overview.storage, "memory");
    assert.equal(overview.database, "ok");
    assert.equal(overview.schemaVersion, Math.max(...MIGRATIONS.map((m) => m.version)));
    assert.equal(overview.schemaVersion, 4);
    assert.equal(overview.version, "0.1.0");
    assert.ok(Math.abs(Date.parse(overview.serverTime) - Date.now()) < 60_000);
  });
});

describe("deleting users", () => {
  test("unknown users are 404 and a teacher with a course is in use", async () => {
    expectError(await admin("DELETE", "/users/nobody"), 404, "USER_NOT_FOUND");
    expectError(await admin("DELETE", "/users/u-teacher-1"), 409, "USER_IN_USE");
    assert.ok(await findUser("u-teacher-1"));
  });

  test("a teacher who wrote course notes is in use", async () => {
    const phone = nextPhone();
    const teacher = await createUser({ role: "teacher", phone, password: "notes-pass-1" });
    const note = await app.inject({
      method: "POST",
      url: "/api/v1/notes",
      headers: await signIn(phone, "notes-pass-1"),
      payload: { courseId: "c-001", bookName: "B", courseCode: "CS 301", title: "N", content: "" },
    });
    assert.equal(note.statusCode, 201, note.body);
    expectError(await admin("DELETE", `/users/${teacher.id}`), 409, "USER_IN_USE");
    // Disabling is the alternative.
    const disabled = await admin("PATCH", `/users/${teacher.id}`, { isActive: false });
    assert.equal(disabled.statusCode, 200, disabled.body);
  });

  test("deleting a student removes their enrollments, work and activity", async () => {
    const posted = await app.inject({
      method: "POST",
      url: "/api/v1/channels/ch-002/messages",
      headers: headers.student2,
      payload: { body: "About to be removed" },
    });
    assert.equal(posted.statusCode, 201, posted.body);
    // Preconditions, so the checks below prove something.
    assert.ok(await store.getSubmission("s-002"));
    assert.ok((await store.getAttendanceRecords("c-001")).some((r) => r.studentId === "u-student-2"));
    assert.equal((await store.getStudentDepartments("u-student-2")).length, 1);
    assert.ok(await store.getEffortScore("u-student-2", "a-001"));

    const res = await admin("DELETE", "/users/u-student-2");
    assert.equal(res.statusCode, 200, res.body);
    assert.deepEqual(res.json(), { data: { success: true } });

    assert.equal(await store.getUser("u-student-2"), undefined);
    assert.ok(!(await listCourses()).some((course) => course.studentIds.includes("u-student-2")));
    for (const channel of ["ch-001", "ch-002"]) {
      assert.ok(!(await store.getChannel(channel))!.memberIds.includes("u-student-2"), channel);
    }
    assert.ok(!(await store.getMessages("ch-002")).some((m) => m.authorId === "u-student-2"));
    assert.equal(await store.getSubmission("s-002"), undefined);
    assert.ok(!(await store.getAttendanceRecords()).some((r) => r.studentId === "u-student-2"));
    assert.deepEqual(await store.getStudentDepartments("u-student-2"), []);
    assert.ok(!(await store.getTelemetryBatches()).some((b) => b.studentId === "u-student-2"));
    assert.equal(await store.getEffortScore("u-student-2", "a-001"), undefined);
    assert.deepEqual(await store.getIntegrityFlags("u-student-2", "a-001"), []);
    assert.ok(!(await integrityRows()).some((row) => row.studentId === "u-student-2"));
    expectError(await login({ phone: STUDENT_2, password: PASSWORD }), 401, "INVALID_CREDENTIALS");

    expectError(await admin("DELETE", "/users/u-student-2"), 404, "USER_NOT_FOUND");
  });
});

describe("deleting courses", () => {
  test("unknown courses are 404", async () => {
    expectError(await admin("DELETE", "/courses/nope"), 404, "COURSE_NOT_FOUND");
  });

  test("deleting a course cascades, after which its teacher can be deleted", async () => {
    const course = (await listCourses()).find((entry) => entry.title === "Database Systems")!;
    const teacherId = course.teacherId;
    expectError(await admin("DELETE", `/users/${teacherId}`), 409, "USER_IN_USE");

    const res = await admin("DELETE", `/courses/${course.id}`);
    assert.equal(res.statusCode, 200, res.body);
    assert.deepEqual(res.json(), { data: { success: true } });
    assert.ok(!(await listCourses()).some((entry) => entry.id === course.id));
    assert.ok(!(await listUsers()).some((user) => user.courseIds.includes(course.id)));
    assert.equal((await admin("DELETE", `/users/${teacherId}`)).statusCode, 200);
  });

  test("deleting a course removes its assignments, work, chat, calendar, attendance and notes", async () => {
    const event = await app.inject({
      method: "POST",
      url: "/api/v1/calendar",
      headers: headers.admin,
      payload: { title: "Course review", kind: "class", startsAt: "2026-12-02T10:00:00.000", courseId: "c-001" },
    });
    assert.equal(event.statusCode, 201, event.body);
    const note = await app.inject({
      method: "POST",
      url: "/api/v1/notes",
      headers: headers.teacher,
      payload: { courseId: "c-001", bookName: "B", courseCode: "CS 301", title: "T", content: "C" },
    });
    assert.equal(note.statusCode, 201, note.body);
    const attendanceBefore = await store.getAttendanceRecords("c-001");
    assert.ok(attendanceBefore.length > 0);
    assert.ok((await store.getMessages("ch-001")).length > 0);
    assert.ok((await integrityRows()).some((row) => row.courseId === "c-001"));
    // The teacher teaches this course and wrote its notes: in use until it goes.
    expectError(await admin("DELETE", "/users/u-teacher-1"), 409, "USER_IN_USE");

    const res = await admin("DELETE", "/courses/c-001");
    assert.equal(res.statusCode, 200, res.body);

    assert.ok(!(await listCourses()).some((course) => course.id === "c-001"));
    for (const id of ["a-001", "a-002", "a-003", "a-004"]) {
      assert.equal(await store.getAssignment(id), undefined, id);
    }
    const assignment = await app.inject({
      method: "GET",
      url: "/api/v1/assignments/a-001",
      headers: headers.admin,
    });
    expectError(assignment, 404, "ASSIGNMENT_NOT_FOUND");
    for (const id of ["s-001", "s-003"]) {
      assert.equal(await store.getSubmission(id), undefined, id);
    }
    for (const id of ["ch-001", "ch-002"]) {
      assert.equal(await store.getChannel(id), undefined, id);
      assert.deepEqual(await store.getMessages(id), [], id);
    }
    const calendar = await store.getCalendarEvents(new Set(["c-001"]));
    assert.ok(!calendar.some((entry) => entry.courseId === "c-001"));
    assert.ok(calendar.some((entry) => entry.id === "e-005"), "institution events stay");
    assert.deepEqual(await store.getAttendanceRecords("c-001"), []);
    assert.deepEqual(await store.getTeacherNotes("c-001"), []);
    assert.deepEqual(await integrityRows(), []);
    assert.ok(!(await store.getTelemetryBatches()).some((b) => b.assignmentId.startsWith("a-00")));
    assert.ok(!(await listUsers()).some((user) => user.courseIds.includes("c-001")));

    // Nothing references the teachers any more (their notes went with the course).
    assert.equal((await admin("DELETE", "/users/u-teacher-1")).statusCode, 200);
    const notesAuthor = (await listUsers("?status=inactive&role=teacher"))[0];
    assert.equal((await admin("DELETE", `/users/${notesAuthor.id}`)).statusCode, 200);
  });
});

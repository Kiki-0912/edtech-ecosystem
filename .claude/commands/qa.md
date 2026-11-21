---
description: QA Engineer — write and run tests for recent changes, probe edge cases, report failures
argument-hint: [area or files to focus on]
---

You are acting as the **QA Engineer**. Follow `CLAUDE.md`. Focus: $ARGUMENTS
(default: everything in the working tree diff).

## 1. Scope the change
Run `git status` and `git diff` (plus `git diff --staged`). List the behaviors
that changed and the component each one belongs to.

## 2. Find coverage gaps and add tests
For each changed behavior, check for an existing test. Write the missing ones:
- **API** in `apps/api/test/<area>.test.ts`:
  ```ts
  import { test } from "node:test";
  import assert from "node:assert/strict";
  import { buildApp } from "../src/create-app";
  // log in via POST /api/v1/auth/login (seeded +15550001001..6 / password123)
  // then app.inject({ method, url, headers: { authorization: `Bearer ${token}` } })
  ```
  Cover the happy path, 401 without a token, 403 for the wrong role, 400/404 for bad
  input, and the response envelope shape. Call `await app.close()` after each test.
- **Flutter** in `apps/app/test/*_test.dart`. Widget tests run under the offline
  client with `SharedPreferences.setMockInitialValues`. API integration tests must
  `markTestSkipped` when `127.0.0.1:4000/health` is unreachable.
- **Rust**: `#[cfg(test)]` unit tests in the touched module.
- **Extension**: no harness. Run `node --check` and write out manual test steps,
  including consent-off behavior and sensitive-field exclusion.

Edge cases to probe: empty and oversized input, missing fields, unauthorized
roles, offline/online parity, TS ↔ Rust effort-score parity, and idempotency of
upserts.

## 3. Run
```bash
npm run typecheck
npx tsx --test 'apps/api/test/**/*.test.ts'
(cd apps/app && flutter analyze --no-fatal-infos && flutter test)
cargo test --manifest-path crates/telemetry-core/Cargo.toml
```
Run only the suites the change touches, and always the suite you added tests
to. To exercise the Flutter integration tests, start `npm run dev:api` in the
background first.

## 4. Report
| Suite | Result | New tests |. List each failure with test name, actual vs
expected, and the likely cause with file:line. **Don't fix production code in
this role.** If a failure is a real bug, say so and recommend `/implement` with
the fix. Fixing a broken *test* you wrote is fine. Distinguish real regressions
from the pre-existing baseline in `CLAUDE.md`.

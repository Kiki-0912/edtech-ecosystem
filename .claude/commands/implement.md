---
description: Senior Engineer — execute an approved plan with minimal, rule-following diffs
argument-hint: [plan reference or extra instructions]
---

You are acting as the **Senior Engineer**. Follow every rule in `CLAUDE.md`.

Input: $ARGUMENTS
Execute the most recent approved plan in this conversation (from `/plan`). If
there is no approved plan and the change touches more than one file, stop and
ask for `/plan` first.

## Rules
- Implement the plan's steps in order. If reality differs from the plan (a
  missing function, a wrong assumption), stop and explain instead of improvising
  a different design.
- Keep diffs minimal. No drive-by refactors or reformatting of untouched code,
  and don't touch uncommitted user changes outside the plan.
- Keep contracts in sync: `@edtech/shared` ↔ API route ↔ Flutter `ApiService` and
  models ↔ `OfflineClient`/`OfflineStore`. Effort scoring changes go in both TS and Rust.
- Write the tests from the plan's test plan alongside the code. New behavior
  without a test is unfinished.
- Follow the conventions: `import type`, the `{ data }` / `{ error: { code, message } }`
  envelopes, `package:edtech_app/...` imports, `theme.dart` tokens, serde camelCase.
- No secrets, no new dependencies unless the plan approved them, and never
  commit.

## Verify the components you touched
- API/shared: `npm run typecheck`, then `npx tsx --test 'apps/api/test/**/*.test.ts'`
- Flutter (in `apps/app`): `flutter analyze --no-fatal-infos`, then `flutter test`
- Rust: `cargo test` and `cargo clippy -- -D warnings` (both with `--manifest-path crates/telemetry-core/Cargo.toml`)
- Extension: `node --check` on each changed `apps/extension/src/*.js`

## Report
List the files changed, one line each, with the check commands and their actual
pass/fail results. Note any deviation from the plan. Suggest `/qa` next.

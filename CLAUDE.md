# EdTech Ecosystem — Claude guide

A monorepo for classroom management, collaboration, and process-based academic
integrity monitoring. It has four deployable pieces plus a shared types package.
`README.md` covers the product. `docs/IMPLEMENTATION_NOTES.md` covers the history.

## Architecture map

| Path | Stack | Responsibility |
| --- | --- | --- |
| `apps/api/` | Fastify 5 + TypeScript (ESM), npm workspace `@edtech/api` | REST API under `/api/v1`. Auth (scrypt + HMAC tokens + SMS codes), courses, classroom, students, departments, attendance, notes, Excel, telemetry ingestion |
| `apps/api/src/create-app.ts` | | Builds the Fastify app: CORS, the global auth `preHandler`, route registration, 404/error handlers. **Every new route module gets registered here.** |
| `apps/api/src/routes/*.ts` | | One `FastifyPluginAsync` per domain |
| `apps/api/src/store/db.ts` | | Seeded **in-memory** data layer and CRUD helpers (`memory.ts` = seed data). `apps/api/db/*.sql` is the reference schema; it is not wired up |
| `apps/api/src/services/effort.ts` | | Effort score + integrity flags. Must stay consistent with `crates/telemetry-core` |
| `api/index.ts` | Vercel function | Serverless entry that reuses `buildApp()`. `vercel.json` rewrites everything here |
| `packages/shared/` | TypeScript, `@edtech/shared` | Domain contracts (users, courses, telemetry, effort, `ApiError` envelopes). Source-only, no build step |
| `apps/app/` | Flutter 3.50 (`material_ui`), `provider` + `go_router` + `http` | Client app: `lib/ui` (design system), `lib/shell` (navigation), `lib/screens/<feature>/`, `lib/models`, `lib/services`, `lib/auth` |
| `apps/app/lib/ui/` | | **Design system.** `tokens.dart` (`AppColors` ThemeExtension, `Tone`, `AppSpacing`, `AppRadius`, `Breakpoints`, `context.colors` / `context.text`), `app_theme.dart`, `components/` (`AppPage`, `SectionCard`, `StatTile`, `StatusBadge`, `AsyncBody`, `showFormSheet`, charts…). Import via `package:edtech_app/ui/ui.dart` |
| `apps/app/lib/router.dart` + `lib/shell/` | | `GoRouter` with `StatefulShellRoute` (one branch per destination, order = `kDestinations`), `refreshListenable: auth`, role guards (`kRoleGuards`). `AppShell` = bottom bar <600px, rail <1024px, sidebar ≥1024px. `navForRole` decides each role's tabs |
| `apps/app/lib/services/api_service.dart` | | Singleton HTTP client for every API call |
| `apps/app/lib/services/offline_client.dart` + `offline_store.dart` | | In-process fake of the **whole API**, persisted with `shared_preferences`. `OFFLINE_MODE` defaults to `true` |
| `apps/extension/` | Manifest V3, plain JS (no build) | "Integrity Lens" telemetry extension: consent gate, signed batch upload |
| `crates/telemetry-core/` | Rust 2021, serde | Native event model and effort-scoring engine (cdylib/staticlib/rlib) |
| `.github/workflows/ci.yml` | | CI. Keep it green; it defines the required checks |

Deploy targets: Vercel (API, `vercel.json`), Netlify (Flutter web, `netlify.toml`),
Docker (`Dockerfile`, `docker-compose.yml`, API on port 4000).

## Commands (run from repo root unless noted)

```bash
# Install
npm install                                   # JS workspaces
(cd apps/app && flutter pub get)

# API
npm run dev:api                               # tsx watch on :4000
npm run build:api                             # tsup → apps/api/dist
npm run typecheck                             # tsc --noEmit for api + shared
npm run test:api                              # API tests (node:test + app.inject, apps/api/test)

# Flutter (from apps/app)
flutter analyze                               # gate: no issues at all
flutter test                                  # widget, flow and layout-matrix tests
(cd ../.. && npm run dev:api) & flutter test test/api_integration_test.dart  # online parity
dart format lib test                          # formatter
flutter build apk --release --dart-define=OFFLINE_MODE=true
flutter build web --release --dart-define=OFFLINE_MODE=false --dart-define=API_BASE_URL=<url> && node scripts/bust_cache.js

# Extension
for f in apps/extension/src/*.js; do node --check "$f"; done
node -e "require('./apps/extension/manifest.json')"

# Rust
cargo test --manifest-path crates/telemetry-core/Cargo.toml
cargo clippy --manifest-path crates/telemetry-core/Cargo.toml -- -D warnings
cargo fmt --manifest-path crates/telemetry-core/Cargo.toml -- --check
```

Baseline after the UI overhaul (2026-11-21): typecheck clean; `npm run test:api`
15 pass; `flutter analyze` reports **no issues** (keep it that way, infos
included); `flutter test` ~89 pass, with `api_integration_test.dart` skipping
unless the API is running (10 pass when it is). Rust: 3 tests pass, clippy clean,
but `cargo fmt --check` already fails — pre-existing, not your regression.

## Workflow rules

1. **Plan before multi-file edits.** If a change touches more than one file, or
   crosses a component boundary (API ↔ app ↔ extension ↔ crate), write a plan
   first (use `/plan`). The plan lists affected files, steps, edge cases, and
   tests. Wait for approval before editing.
2. **Tests for every new behavior.** Each new behavior or bug fix ships with a
   test in the matching suite:
   - API: `apps/api/test/<area>.test.ts`. Use `node:test`, `node:assert/strict`,
     `buildApp()` and `app.inject(...)`. No network, no real port.
   - Flutter: `apps/app/test/*_test.dart`. Put widget tests under the offline
     client. Integration tests must skip when the API is unreachable (follow
     `api_integration_test.dart`).
   - Rust: `#[cfg(test)] mod tests` in the same file.
   - Extension: there is no test harness. Keep pure logic in small functions
     and verify with `node --check`, then describe a manual test.
3. **Run the relevant checks before saying you're done.** Report real output.
   Never claim a check passed if you didn't run it.
4. **Minimal diffs.** Don't reformat untouched code, rename unrelated symbols,
   or "clean up" outside the task. The working tree often has uncommitted user
   work, so never revert or overwrite changes you didn't make.
5. **Never commit or push unless asked.** Never commit `.env*`, `*.apk`,
   `build/`, `target/`, or `node_modules/`.

## Architectural guardrails

- **API contract changes are 3-way.** A route shape change must update
  `packages/shared/src/index.ts`, the Flutter `ApiService` and model `fromJson`,
  **and `OfflineClient`/`OfflineStore`**, because the default APK build runs offline
  and silently diverges otherwise. The extension also matters if it touches
  `/auth/login` or `/telemetry/batches`.
- **Effort scoring exists twice** (`apps/api/src/services/effort.ts` and
  `crates/telemetry-core/src/lib.rs`). Change both or neither, with matching tests.
- **Auth:** every route except `/`, `/api`, `/health*`, and `/api/v1/auth/*` is
  protected by the global `preHandler` in `create-app.ts`. Role checks use
  `requireRoles(...)` from `middleware/auth.ts`. Never widen
  `PUBLIC_PREFIXES` without explicit approval.
- **Errors** always use the envelope `{ error: { code: "UPPER_SNAKE", message } }`.
  Success responses use `{ data: ... }`.
- **Config** comes from env via `apps/api/src/config.ts` only. Never hard-code
  secrets. The `AUTH_SECRET` dev fallback is for local use only.
- **Privacy (extension):** never capture key content, password or hidden
  inputs, or `[data-sensitive]` elements, and never record or upload
  anything before consent. Batches stay HMAC-signed.
- **Persistence** is in-memory (`store/db.ts`). Don't add a database dependency
  without a plan. Vercel cold starts reset state.
- Pinned on purpose: `shared_preferences_android: 2.4.28` (avoids an NDK
  requirement). Don't bump it.

## Coding conventions

General (`.editorconfig`): UTF-8, LF, 2-space indent (Rust uses 4), final
newline, max line length 100 for Dart and Rust.

**TypeScript (API/shared)**
- ESM, `strict`, `verbatimModuleSyntax`. Use `import type` for type-only imports.
- Files are `kebab-case.ts`. Identifiers are `camelCase`, types and interfaces
  are `PascalCase`, and constants are `UPPER_SNAKE`.
- Route modules export a `FastifyPluginAsync`, are registered with a
  `/api/v1` prefix, and use resource-plural paths (`/notes`, `/notes/:id`).
- Match the quote style of the file you're editing. Avoid new `any`; type
  request params/query/body.
- Keep shared domain types in `@edtech/shared`. Don't duplicate them locally.

**Dart/Flutter**
- Run `dart format`. Follow `flutter_lints` plus `prefer_const_constructors`,
  `prefer_final_locals`, and `avoid_print`.
- Files are `snake_case.dart`. Use package imports
  (`package:edtech_app/...`), not relative ones.
- Import `material_ui/material_ui.dart`, not `flutter/material.dart` (deprecated
  since Flutter 3.47; tests must use the same import or type finders miss).
- Screens live in `lib/screens/<feature>/<feature>_screen.dart`; reusable UI goes
  in `lib/ui/components`. Models are immutable with `fromJson`/`toJson`.
- **Design-system rules:** screens use only `lib/ui` building blocks and tokens —
  `context.colors`, `context.text`, `AppSpacing`, `AppRadius`, `Tone`. No
  `Color(0x…)`, no `Colors.*` (except `Colors.transparent`), no literal font sizes.
  Orange (`accent`) is for primary actions and active navigation only; status
  uses semantic tones (`attendanceTone`, `StatusBadge`). Orange *text* uses
  `accentText` (contrast).
- Every page wraps content in `AppPage` and handles loading/error/empty through
  `AsyncBody`. Forms open with `showFormSheet` (sheet on phone, dialog on wide).
  Destructive actions go through `confirmDialog`.
- Give interactive controls a stable `Key('feature-action')`; tests find by key.
- New screens must be added to `test/layout_matrix_test.dart` (all roles × phone
  / tablet / desktop × light / dark, plus 1.3× text).
- New tabs: add an `AppDestination` + branch in the same order in
  `router.dart`, update `navForRole`, and guard role-only paths in `kRoleGuards`.
- All HTTP goes through `ApiService`; anything it calls must also work in
  `OfflineClient`/`OfflineStore` (the default build is offline).

**Rust**
- `rustfmt` + `clippy -D warnings`. Serde structs use `rename_all = "camelCase"`
  to match the TS contracts.

**Extension**
- Plain browser JS with no bundler and no new dependencies. Keep the MV3 service
  worker stateless and use `chrome.storage`.

**Commits:** Conventional Commits with a scope, for example
`feat(api): ...`, `fix(app): ...`, `chore(ext): ...`, `test(core): ...`.
Valid scopes are `api`, `app`, `ext`, `core`, `shared`, `ci`, `docs`, `deploy`.

## Team commands

`/plan` → `/implement` → `/qa` → `/review` → `/ship` (see `.claude/commands/`).

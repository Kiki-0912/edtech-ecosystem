---
description: Release Engineer — run all checks, stage, write a conventional commit, draft a PR summary
argument-hint: [optional commit scope/notes]
---

You are acting as the **Release Engineer**. Follow `CLAUDE.md`. Notes: $ARGUMENTS

## 1. Full check suite (mirrors `.github/workflows/ci.yml`)
Run each of these and record pass/fail:
```bash
npm run typecheck
npm run build:api
npx tsx --test 'apps/api/test/**/*.test.ts'       # if the dir exists
for f in apps/extension/src/*.js; do node --check "$f"; done
node -e "require('./apps/extension/manifest.json')"
(cd apps/app && flutter analyze --no-fatal-infos && flutter test)
cargo test   --manifest-path crates/telemetry-core/Cargo.toml
cargo clippy --manifest-path crates/telemetry-core/Cargo.toml -- -D warnings
```
If anything fails that isn't in the `CLAUDE.md` baseline, **stop**: report it
and don't stage. Note that CI runs plain `flutter analyze` (fatal infos) and
`cargo fmt --check`, both of which currently fail on the pre-existing baseline.
Mention it, but don't block on it.

## 2. Stage
Run `git status`. Stage only files that belong to this change, by explicit path
(never `git add -A` or `git add .`). Never stage `.env*`, `*.apk`, `build/`,
`target/`, `node_modules/`, screenshots or `.docx`/`.pdf` artifacts, or
unrelated uncommitted work. If you're unsure whether a modified file belongs,
ask. Show `git diff --staged --stat`.

## 3. Commit message
Conventional Commits: `type(scope): imperative summary` (≤72 chars). Types are
feat, fix, refactor, perf, test, docs, chore, ci, and build. Scopes are api, app,
ext, core, shared, ci, docs, and deploy. The body explains the *why* and any
contract or offline-parity impact. Mark breaking changes with `!` and a
`BREAKING CHANGE:` footer. Show the message and **ask for confirmation before
running `git commit`**. Never push unless explicitly asked.

## 4. PR summary
Draft (don't create) a PR description:
- **Summary**: 1–3 bullets
- **Changes by component**: API / shared / app / extension / core
- **Contract and offline-parity impact**
- **Testing**: commands run and results, new tests added
- **Risks and rollback**
- **Checklist**: typecheck ✅, tests ✅, review ✅, no secrets ✅

If the user wants the PR opened, use `gh pr create` against `main` after they
confirm.

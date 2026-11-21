---
description: Staff Architect — turn a feature or bug into an implementation spec (no code)
argument-hint: <feature or bug description>
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(ls:*)
---

You are acting as the **Staff Architect** for this monorepo. Follow `CLAUDE.md`.

Task: $ARGUMENTS

**Do not edit or create any files.** Investigate first, then produce a spec.

## Investigate
1. Read the relevant code paths. Start with the architecture map in `CLAUDE.md`.
   Name the components involved: API, shared types, Flutter app (online
   `ApiService` **and** offline `OfflineClient`/`OfflineStore`), extension, Rust core.
2. Check `git status` so the plan doesn't trample uncommitted work.
3. For a bug, identify the root cause with file:line evidence, not a guess.

## Output this spec

### Summary
One paragraph: what changes and why.

### Affected files
A table of `path` | change (new/modify) | reason.

### Implementation steps
Numbered, ordered, and small enough that each could be reviewed alone. Name
functions, routes, and types explicitly.

### Contract impact
API request/response shape changes, `@edtech/shared` types, Flutter model and
offline-client parity, extension, and effort-scoring parity (TS ↔ Rust). Write
"none" if none apply.

### Edge cases and risks
Auth/role checks, empty and invalid input, offline mode, Vercel cold-start state
loss, privacy and consent (extension), backwards compatibility.

### Test plan
The specific tests to add per suite (API `node:test` + `app.inject`, Flutter
widget/integration, Rust unit), plus the check commands that must pass.

### Open questions
Anything the user must decide. Stop there and ask for approval before anyone
runs `/implement`.

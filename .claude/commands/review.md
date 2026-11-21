---
description: Security & Code Reviewer — audit the git diff and output actionable fixes
argument-hint: [base ref, default HEAD]
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git status:*), Bash(git log:*), Bash(git show:*)
---

You are acting as the **Security & Code Reviewer**. Use `CLAUDE.md` as the
rulebook. **Read-only: don't edit files.**

Base ref: "$ARGUMENTS" (use `HEAD` if empty). Diff under review: run
`git diff <base>` plus `git status` for
untracked files (read those in full). Read surrounding code where you need
context. Don't review the diff in isolation.

## Checklist
**Correctness:** logic errors, off-by-one, null/undefined handling, unawaited
promises, `mounted` checks after `await` in Flutter, state not updating, and
contract drift between `@edtech/shared`, the API, `ApiService`, and `OfflineClient`.

**Security (this repo specifically):**
- New routes are covered by the global auth `preHandler`. `PUBLIC_PREFIXES` is
  not widened. Role-restricted actions use `requireRoles`. No IDOR: callers
  can't read or modify other users' data via `:id`.
- Input validation on body, params, and query. Excel import parsing is safe.
- Token and HMAC handling: constant-time compares, no secrets in code or logs,
  `AUTH_SECRET` only from config.
- Errors don't leak internals (5xx uses `INTERNAL_ERROR`). No PII in logs.
- Extension: no key content, password, hidden, or `[data-sensitive]` capture,
  nothing before consent, signed batches intact, no broadened `host_permissions`.
- CORS, and no new `.env` or secrets in the diff.

**Performance:** O(n²) scans in `store/db.ts` hot paths, unbounded lists,
needless Flutter rebuilds (missing `const`, provider listeners too broad),
work on the extension's hot keystroke path.

**Style and tests:** naming and import conventions from `CLAUDE.md`, minimal diff,
new behavior has tests, no `print`, no hard-coded colors outside `theme.dart`.

## Output
Group findings by severity: **🔴 Blocker / 🟠 Should fix / 🟡 Nit**. Each one
gets `path:line`, what's wrong, a concrete failure scenario, and the exact fix
(a code snippet when useful). Skip vague or speculative items. End with a
verdict: **Approve / Approve with fixes / Request changes**.

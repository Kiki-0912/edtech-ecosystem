#!/usr/bin/env bash
# PostToolUse hook: auto-format the file Claude just wrote or edited.
# It skips any formatter that isn't installed. It exits 0, except exit 2 on an
# extension JS syntax error, which sends that error back to Claude.
#   .dart -> dart format      .rs -> rustfmt (edition 2021)
#   apps/extension/**/*.js -> node --check (prints a syntax error to Claude via stderr)
# TS has no formatter configured in this repo. If you add Prettier later, uncomment:
#   *.ts) command -v npx >/dev/null && npx --no-install prettier --write "$f" ;;
set -u
f=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$f" ] && [ -f "$f" ] || exit 0

case "$f" in
  */build/*|*/target/*|*/node_modules/*|*/.dart_tool/*) exit 0 ;;
  *.dart) command -v dart >/dev/null && dart format "$f" >/dev/null 2>&1 ;;
  *.rs)   command -v rustfmt >/dev/null && rustfmt --edition 2021 "$f" >/dev/null 2>&1 ;;
  */apps/extension/*.js)
    if ! out=$(node --check "$f" 2>&1); then
      echo "node --check failed for $f:" >&2; echo "$out" >&2; exit 2
    fi ;;
esac
exit 0

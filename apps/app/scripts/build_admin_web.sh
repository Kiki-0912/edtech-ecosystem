#!/usr/bin/env bash
# Builds the admin console (lib/main_admin.dart) as its own static web app in
# build/admin_web, ready to deploy as a separate Netlify site.
#
#   API_BASE_URL=https://your-api.example.com scripts/build_admin_web.sh
#
# The console always talks to the live API (it never uses the offline demo
# backend), so API_BASE_URL is required. If the API's CORS_ORIGIN is not "*",
# add this site's origin to it (comma-separated), e.g.
#   CORS_ORIGIN=https://edtech-web.netlify.app,https://edtech-admin.netlify.app
# or the browser blocks every console request, sign-in included.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$APP_DIR/build/admin_web"
cd "$APP_DIR"

flutter build web --release \
  -t lib/main_admin.dart \
  --dart-define=API_BASE_URL="${API_BASE_URL:?set API_BASE_URL}" \
  -o "$OUT_DIR"

# Single-page app: every path serves index.html (same as the root netlify.toml).
printf '/*  /index.html  200\n' > "$OUT_DIR/_redirects"

# Same security headers and no-cache rules as the root netlify.toml. Files in
# assets/ and canvaskit/ keep fixed names across builds (no content hash), so
# they must not be cached as immutable: Netlify's default (revalidate with an
# ETag) applies to them instead.
cat > "$OUT_DIR/_headers" <<'HEADERS'
/*
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin

/index.html
  Cache-Control: no-cache, no-store, must-revalidate

/main.dart.js
  Cache-Control: no-cache, no-store, must-revalidate

/flutter_bootstrap.js
  Cache-Control: no-cache, no-store, must-revalidate

/flutter_service_worker.js
  Cache-Control: no-cache, no-store, must-revalidate
HEADERS

# web/index.html and web/manifest.json are shared with the main app; rename
# them so browser tabs, bookmarks and an installed app tell the two apart.
node - "$OUT_DIR" <<'NODE'
const fs = require("fs");
const path = require("path");
const dir = process.argv[2];
const html = path.join(dir, "index.html");
fs.writeFileSync(
  html,
  fs
    .readFileSync(html, "utf8")
    .replace(/<title>[^<]*<\/title>/, "<title>Edu-tech Admin</title>")
    .replace(
      /(<meta name="apple-mobile-web-app-title" content=")[^"]*"/,
      '$1Edu-tech Admin"',
    ),
);
const manifestPath = path.join(dir, "manifest.json");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
manifest.name = "Edu-tech Admin";
manifest.short_name = "Edu-tech Admin";
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n");
NODE

node "$APP_DIR/scripts/bust_cache.js" "$OUT_DIR"
echo "Admin console built in $OUT_DIR"

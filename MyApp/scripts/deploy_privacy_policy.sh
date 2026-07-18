#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/vijaygoyal/MyiOSApp"
WEB_SOURCE="$ROOT/shadyspade-web"
TMP_DIR="/private/tmp/shadyspade-web-clean-privacy"
WORKER_NAME="winter-band-18fa"
DOMAIN="shadyspade.vijaygoyal.org"
COMPATIBILITY_DATE="2026-06-22"

required_paths=(
  "$WEB_SOURCE/index.html"
  "$WEB_SOURCE/privacy"
  "$WEB_SOURCE/support"
)

for path in "${required_paths[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "Missing required path: $path" >&2
    exit 1
  fi
done

if ! command -v npx >/dev/null 2>&1; then
  echo "npx is required to run Wrangler." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required for live verification." >&2
  exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "rg is required for live verification." >&2
  exit 1
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

cp -R \
  "$WEB_SOURCE/index.html" \
  "$WEB_SOURCE/privacy" \
  "$WEB_SOURCE/support" \
  "$TMP_DIR"

echo "Deploying clean static privacy site from $TMP_DIR"
npx wrangler deploy "$TMP_DIR" \
  --name "$WORKER_NAME" \
  --assets "$TMP_DIR" \
  --compatibility-date "$COMPATIBILITY_DATE" \
  --domain "$DOMAIN"

echo "Verifying live privacy policy text..."
curl -L --max-time 15 "https://$DOMAIN/privacy" \
  | rg "Last Updated|Allow Score Uploads|Play Without Uploading Scores|only if you allow score uploads"

echo "Verifying Wrangler cache paths are not public..."
cache_status="$(curl -I -s --max-time 15 "https://$DOMAIN/.wrangler/cache/wrangler-account.json" | awk 'NR==1 { print $2 }')"
if [[ "$cache_status" != "404" ]]; then
  echo "Expected .wrangler cache path to return 404, got: $cache_status" >&2
  exit 1
fi

echo "Privacy policy deploy verified."

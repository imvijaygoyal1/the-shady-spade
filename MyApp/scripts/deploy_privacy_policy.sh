#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/vijaygoyal/MyiOSApp"
WEB_SOURCE="$ROOT/shadyspade-web"
TMP_DIR="/private/tmp/shadyspade-web-clean-privacy"
ASSETS_DIR="$TMP_DIR/assets"
WORKER_NAME="winter-band-18fa"
DOMAIN="shadyspade.vijaygoyal.org"
COMPATIBILITY_DATE="2026-06-22"

required_paths=(
  "$WEB_SOURCE/index.html"
  "$WEB_SOURCE/.well-known"
  "$WEB_SOURCE/apple-app-site-association"
  "$WEB_SOURCE/join"
  "$WEB_SOURCE/privacy"
  "$WEB_SOURCE/scorekeeper"
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
mkdir -p "$ASSETS_DIR"

cp -R \
  "$WEB_SOURCE/index.html" \
  "$WEB_SOURCE/.well-known" \
  "$WEB_SOURCE/apple-app-site-association" \
  "$WEB_SOURCE/join" \
  "$WEB_SOURCE/privacy" \
  "$WEB_SOURCE/scorekeeper" \
  "$WEB_SOURCE/support" \
  "$ASSETS_DIR"

cat > "$TMP_DIR/worker.js" <<'WORKER'
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    const fetchAsset = (pathname) => {
      const assetUrl = new URL(request.url);
      assetUrl.pathname = pathname;
      assetUrl.search = "";
      return env.ASSETS.fetch(new Request(assetUrl.toString(), {
        method: "GET",
        headers: request.headers
      }));
    };

    const codeFromPath = () => {
      const parts = path.split("/").filter(Boolean);
      return (parts[parts.length - 1] || "")
        .replace(/[^a-z0-9]/gi, "")
        .slice(0, 6)
        .toUpperCase();
    };

    const fallbackWithCode = async (pathname, elementId) => {
      const response = await fetchAsset(pathname);
      const html = await response.text();
      const code = codeFromPath() || "------";
      const headers = new Headers(response.headers);
      headers.set("content-type", "text/html; charset=UTF-8");
      return new Response(
        html.replace(`id="${elementId}">------`, `id="${elementId}">${code}`),
        {
          status: response.status,
          statusText: response.statusText,
          headers
        }
      );
    };

    if (path === "/.wrangler" || path.startsWith("/.wrangler/")) {
      return new Response("Not found", { status: 404 });
    }

    if (path === "/.well-known/apple-app-site-association" || path === "/apple-app-site-association") {
      const response = await fetchAsset(path);
      const headers = new Headers(response.headers);
      headers.set("content-type", "application/json");
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers
      });
    }

    if (path.match(/^\/(?:shadyspade\/)?join\/[A-Za-z0-9-_%]+\/?$/)) {
      return fallbackWithCode("/join/index.html", "room-code");
    }

    if (path.match(/^\/(?:shadyspade\/)?scorekeeper\/[A-Za-z0-9-_%]+\/?$/)) {
      return fallbackWithCode("/scorekeeper/index.html", "scorekeeper-code");
    }

    return env.ASSETS.fetch(request);
  }
};
WORKER

cat > "$TMP_DIR/wrangler.jsonc" <<CONFIG
{
  "name": "$WORKER_NAME",
  "main": "worker.js",
  "compatibility_date": "$COMPATIBILITY_DATE",
  "routes": [
    {
      "pattern": "$DOMAIN",
      "custom_domain": true
    }
  ],
  "assets": {
    "directory": "assets",
    "binding": "ASSETS",
    "run_worker_first": [
      "/.well-known/apple-app-site-association",
      "/apple-app-site-association",
      "/join/*",
      "/scorekeeper/*",
      "/shadyspade/join/*",
      "/shadyspade/scorekeeper/*",
      "/.wrangler/*"
    ]
  }
}
CONFIG

echo "Deploying clean static privacy site from $ASSETS_DIR"
npx wrangler deploy --config "$TMP_DIR/wrangler.jsonc"

echo "Verifying live privacy policy text..."
curl -L --max-time 15 "https://$DOMAIN/privacy" \
  | rg "Last Updated|Allow Score Uploads|Play Without Uploading Scores|only if you allow score uploads"

echo "Verifying Wrangler cache paths are not public..."
cache_status="$(curl -I -s --max-time 15 "https://$DOMAIN/.wrangler/cache/wrangler-account.json" | awk 'NR==1 { print $2 }')"
if [[ "$cache_status" != "404" ]]; then
  echo "Expected .wrangler cache path to return 404, got: $cache_status" >&2
  exit 1
fi

echo "Verifying universal link assets..."
aasa_headers="$(mktemp)"
curl -L --max-time 15 -D "$aasa_headers" "https://$DOMAIN/.well-known/apple-app-site-association" \
  | rg "7B5U5LACV3.com.vijaygoyal.theshadyspade|/join/\\*|/scorekeeper/\\*"
rg -i "content-type: application/json" "$aasa_headers"

join_page="$(mktemp)"
curl -L --max-time 15 "https://$DOMAIN/join/ABC123" > "$join_page"
rg "Join The Shady Spade" "$join_page"
rg "ABC123" "$join_page"

scorekeeper_page="$(mktemp)"
curl -L --max-time 15 "https://$DOMAIN/scorekeeper/HOST01" > "$scorekeeper_page"
rg "Watch Live Scorecard" "$scorekeeper_page"
rg "HOST01" "$scorekeeper_page"

echo "Static site deploy verified."

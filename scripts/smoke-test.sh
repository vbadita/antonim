#!/usr/bin/env bash
# Post-deploy check through the PUBLIC path (Cloudflare -> nginx -> proxy -> function -> Gemini).
#   usage: scripts/smoke-test.sh <api-url> <expected-version>
# Passes only if: HTTP 200, JSON with a non-empty "antonime" list, and the
# X-Antonime-Version header equals the version just deployed (not an old one).
set -euo pipefail
URL=$1
EXPECTED=$2
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

for attempt in 1 2 3 4; do
  # Unique extra parameter: a new nginx cache key, so this cannot be a cached
  # answer from the previous version. The proxy ignores it.
  code=$(curl -sS -o "$tmp/body" -D "$tmp/headers" -w '%{http_code}' --max-time 70 \
    "$URL?cuvant=bun&smoke=$EXPECTED-$attempt-$RANDOM" || echo 000)
  version=$(grep -i '^x-antonime-version:' "$tmp/headers" | cut -d' ' -f2 | tr -d '\r' || true)
  if [ "$code" = 200 ] && [ "$version" = "$EXPECTED" ] && python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert isinstance(d.get("antonime"), list) and d["antonime"], d
' "$tmp/body" 2>/dev/null; then
    echo "smoke OK: HTTP $code, version $version, $(cat "$tmp/body")"
    exit 0
  fi
  # 429 (global cap) and 502 (Gemini slow) are transient: wait and retry.
  echo "attempt $attempt: HTTP $code, version '${version}', body: $(head -c 200 "$tmp/body")"
  sleep 20
done
echo "smoke test FAILED" >&2
exit 1

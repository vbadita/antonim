#!/usr/bin/env bash
# Pull-based deploy of the page (run by antonime-frontend-sync.timer).
# Nothing connects INTO the VM: it pulls from GitHub, like a GitOps agent.
#
#  1. newest commit on main that touched frontend/index.html
#  2. deploy only if that commit's CI "test" check succeeded
#  3. download the file AT THAT COMMIT (immutable URL), sanity-check it
#  4. stamp the version, swap it in atomically (readers never see half a file)
set -euo pipefail
REPO=${REPO:-vbadita/antonim}
FILE=frontend/index.html
WEB_ROOT=${WEB_ROOT:-/srv/antonim}
STATE=${STATE_DIRECTORY:-/var/lib/antonime-frontend}/deployed-sha
API=https://api.github.com/repos/$REPO
UA="antonime-frontend-sync (+https://github.com/$REPO)"

log() { printf '{"event":"frontend_sync","result":"%s","sha":"%s","detail":"%s"}\n' "$1" "${2:-}" "${3:-}"; }
gh_api() { curl -fsS --max-time 20 -H "Accept: application/vnd.github+json" -A "$UA" "$@"; }

sha=$(gh_api "$API/commits?sha=main&path=$FILE&per_page=1" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["sha"])')
short=${sha:0:7}

deployed=$(cat "$STATE" 2>/dev/null || true)
if [ "$sha" = "$deployed" ]; then
  log up_to_date "$short"
  exit 0
fi

conclusion=$(gh_api "$API/commits/$sha/check-runs?check_name=test" \
  | python3 -c 'import json,sys; r=json.load(sys.stdin)["check_runs"]; print(r[0]["conclusion"] if r else "none")')
if [ "$conclusion" != success ]; then
  log waiting_for_ci "$short" "test check: $conclusion"
  exit 0
fi

tmp=$(mktemp "$WEB_ROOT/.index.html.XXXXXX")
trap 'rm -f "$tmp"' EXIT
curl -fsS --max-time 20 -A "$UA" "https://raw.githubusercontent.com/$REPO/$sha/$FILE" -o "$tmp"

size=$(stat -c %s "$tmp")
if [ "$size" -lt 1000 ] || [ "$size" -gt 200000 ] \
  || ! grep -q 'http-equiv="Content-Security-Policy"' "$tmp" \
  || ! grep -q '__VERSION__' "$tmp"; then
  log rejected "$short" "sanity check failed (size $size)"
  exit 1
fi

sed -i "s/__VERSION__/$short/g" "$tmp"
chmod 0644 "$tmp"
mv -f "$tmp" "$WEB_ROOT/index.html"   # rename(2): atomic on the same filesystem
trap - EXIT
printf '%s\n' "$sha" > "$STATE"
log deployed "$short" "previous ${deployed:0:7}"

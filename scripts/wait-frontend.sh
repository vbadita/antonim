#!/usr/bin/env bash
# CI: wait until the LIVE page reports the expected version. The VM pulls new
# pages itself (frontend-sync, every 3 min, only after CI "test" succeeded),
# so CI cannot push; it verifies that the pull happened.
#   usage: scripts/wait-frontend.sh <page-url> <expected-short-sha>
set -euo pipefail
URL=$1
EXPECTED=$2
for i in $(seq 1 40); do   # 40 x 20 s = up to ~13 min
  live=$(curl -fsS --max-time 15 "$URL" | sed -n 's/.*<meta name="antonime-version" content="\([^"]*\)".*/\1/p' || true)
  if [ "$live" = "$EXPECTED" ]; then
    echo "page is live at version $live (after ~$(( (i - 1) * 20 ))s)"
    exit 0
  fi
  echo "check $i: live version '${live}', waiting for $EXPECTED"
  sleep 20
done
echo "page never reached $EXPECTED" >&2
exit 1

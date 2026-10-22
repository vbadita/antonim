#!/usr/bin/env bash
# End-to-end check of the LIVE page in a real headless Chrome (CI: the browser
# preinstalled on GitHub's ubuntu-24.04 x64 runner). Loads /antonim/?cuvant=<word>,
# lets the JavaScript call the API, then checks the rendered DOM has antonym
# chips and that Chrome logged no CSP violation.
#   usage: scripts/e2e-page.sh [page-url] [word]
set -euo pipefail
URL=${1:-https://apps.badita.com/antonim/}
WORD=${2:-bun}
CHROME=${CHROME:-google-chrome}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

"$CHROME" --version
# --timeout: dump the DOM after 25 s of real time (the API answers in < 10 s).
timeout 90 "$CHROME" --headless=new --disable-gpu --no-first-run --enable-logging=stderr --v=0 \
  --timeout=25000 --dump-dom "$URL?cuvant=$WORD" >"$tmp/dom.html" 2>"$tmp/console.log"

python3 - "$tmp/dom.html" "$tmp/console.log" <<'PY'
import re, sys
dom = open(sys.argv[1], encoding="utf-8").read()
console = open(sys.argv[2], encoding="utf-8", errors="replace").read()
chips = re.findall(r'<button type="button" class="chip">([^<]*)</button>', dom)
status = re.search(r'<p id="status"[^>]*>([^<]*)</p>', dom)
csp = [l for l in console.splitlines() if "Content Security Policy" in l or "Refused to" in l]
print("status line:", status.group(1) if status else None)
print("chips:", chips)
print("CSP violations:", csp or "none")
sys.exit(0 if chips and not csp else 1)
PY

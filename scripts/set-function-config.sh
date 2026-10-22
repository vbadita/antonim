#!/usr/bin/env bash
# Set the function's config from the environment (GEMINI_API_KEY, GEMINI_MODEL).
#   usage: scripts/set-function-config.sh <function-ocid>
# The key goes through a 0600 temp file (--config file://...), never argv:
# command lines are visible to every process on the machine.
# Note: an update REPLACES the whole config map, so every key is set each time.
set -euo pipefail
FUNCTION_ID=$1
: "${GEMINI_API_KEY:?GEMINI_API_KEY is not set}" "${GEMINI_MODEL:?GEMINI_MODEL is not set}"
export SUPPRESS_LABEL_WARNING=True

umask 077
cfg=$(mktemp)
trap 'rm -f "$cfg"' EXIT
python3 -c '
import json, os, sys
json.dump({k: os.environ[k] for k in ("GEMINI_API_KEY", "GEMINI_MODEL")}, open(sys.argv[1], "w"))
' "$cfg"

oci fn function update container-function --function-id "$FUNCTION_ID" \
  --config "file://$cfg" --force >/dev/null
# Show what is set without revealing the key.
oci fn function get --function-id "$FUNCTION_ID" --query 'data.config' --output json | python3 -c '
import json, sys
c = json.load(sys.stdin)
print("config:", {k: (v if k == "GEMINI_MODEL" else f"<{len(v)} chars>") for k, v in c.items()})'

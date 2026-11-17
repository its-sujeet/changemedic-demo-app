#!/usr/bin/env bash
# Replay a real endpoint and report its status codes. The same numbers
# ChangeMedic records appear here, so a developer can check the probe itself.
set -euo pipefail
APP_URL="${APP_URL:-http://localhost:8001}"
PROBE_PATH="${PROBE_PATH:-/charge}"
PROBE_METHOD="${PROBE_METHOD:-POST}"
PROBE_BODY="${PROBE_BODY:-{\"amount\":5000}}"
REQUESTS="${REQUESTS:-20}"
EXPECT_BELOW="${EXPECT_BELOW:-400}"

ok=0; bad=0
declare -A codes
for _ in $(seq 1 "$REQUESTS"); do
  args=(-s -o /dev/null -w '%{http_code}' -X "$PROBE_METHOD" -H 'content-type: application/json')
  [[ "$PROBE_METHOD" != "GET" ]] && args+=(--data "$PROBE_BODY")
  code="$(curl "${args[@]}" "$APP_URL$PROBE_PATH" || echo 000)"
  codes[$code]=$(( ${codes[$code]:-0} + 1 ))
  if [[ "$code" =~ ^[0-9]+$ ]] && (( code < EXPECT_BELOW )); then ok=$((ok+1)); else bad=$((bad+1)); fi
done
for code in "${!codes[@]}"; do echo "$code: ${codes[$code]}"; done | sort
echo "healthy=$ok failed=$bad of $REQUESTS"
(( bad == 0 ))

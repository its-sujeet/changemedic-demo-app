#!/usr/bin/env bash
# End-to-end harness: healthy probe -> alert -> incident -> evidence.
set -euo pipefail
source "$(dirname "$0")/cm-auth.sh"
cm_login
PROJECT="${PROJECT:-checkout-api-demo}"

echo "==> 1. probe the running app"
"$(dirname "$0")/probe.sh" || true

echo "==> 2. fire an Alertmanager alert"
"$(dirname "$0")/send-alert.sh"

echo "==> 3. wait for the incident"
for _ in $(seq 1 30); do
  out="$(cm_api GET "/incidents?project=$PROJECT&limit=1")"
  id="$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["id"] if d else "")' 2>/dev/null || true)"
  if [[ -n "$id" ]]; then break; fi
  sleep 2
done
: "${id:?no incident was created}"
echo "incident: $id"
echo "detail:  $CM_URL/#/projects/$PROJECT/incidents/$id"
echo "report:  $CM_URL/incidents/$id/report"
echo "archive: $CM_URL/incidents/$id/capsule.tar.gz"

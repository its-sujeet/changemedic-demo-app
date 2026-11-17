#!/usr/bin/env bash
# Register any HTTP service with ChangeMedic. Points it at one probe and,
# optionally, connects the GitHub repo that deploys it.
set -euo pipefail
source "$(dirname "$0")/cm-auth.sh"

PROJECT="${PROJECT:-checkout-api-demo}"
SERVICE="${SERVICE:-checkout-api}"
NAMESPACE="${NAMESPACE:-demo}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
REPO="${REPO:-its-sujeet/changemedic-demo-app}"
BRANCH="${BRANCH:-main}"
WORKFLOW="${WORKFLOW:-deploy.yml}"
PROBE_PATH="${PROBE_PATH:-/charge}"
PROBE_METHOD="${PROBE_METHOD:-POST}"
PROBE_BODY="${PROBE_BODY:-{\"amount\":5000}}"
REQUESTS="${REQUESTS:-20}"

cm_login
payload="$(python3 - <<'PY'
import json, os
print(json.dumps({
  "name": os.getenv("PROJECT", "checkout-api-demo"),
  "slug": os.getenv("PROJECT", "checkout-api-demo"),
  "service": os.getenv("SERVICE", "checkout-api"),
  "namespace": os.getenv("NAMESPACE", "demo"),
  "environment": os.getenv("ENVIRONMENT", "staging"),
  "probe": {
    "method": os.getenv("PROBE_METHOD", "POST"),
    "path": os.getenv("PROBE_PATH", "/charge"),
    "headers": {"content-type": "application/json"},
    "body": json.loads(os.getenv("PROBE_BODY", '{"amount":5000}')),
    "expect_status_below": 400,
    "requests": int(os.getenv("REQUESTS", "20")),
  },
}))
PY
)"
echo "==> register $PROJECT ($SERVICE/$NAMESPACE)"
cm_api PUT "/projects/$PROJECT" "$payload" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id") or d)'

if [[ -n "${GITHUB_TOKEN:-}" || "${CONNECT_GITHUB:-false}" == "true" ]]; then
  gh_payload="$(python3 - <<'PY'
import json, os
p = {"repo": os.environ["REPO"], "branch": os.getenv("BRANCH", "main"),
     "workflow": os.getenv("WORKFLOW", "deploy.yml"), "dispatch": True}
if os.getenv("GITHUB_TOKEN"): p["token"] = os.environ["GITHUB_TOKEN"]
if os.getenv("WEBHOOK_SECRET"): p["secret"] = os.environ["WEBHOOK_SECRET"]
print(json.dumps(p))
PY
)"
  echo "==> connect $REPO"
  cm_api PUT "/projects/$PROJECT/github" "$gh_payload" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("webhook_url") or d)'
fi
echo "==> console: $CM_URL/#/projects/$PROJECT"

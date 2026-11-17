#!/usr/bin/env bash
# Send a signed GitHub push without needing GitHub to reach your laptop.
set -euo pipefail
CM_URL="${CM_URL:-http://localhost:8080}"
REPO="${REPO:-its-sujeet/changemedic-demo-app}"
BRANCH="${BRANCH:-main}"
SHA="${SHA:-$(printf '%040x' $((RANDOM+RANDOM)))}"
MESSAGE="${MESSAGE:-feat: demo push}"
SECRET="${WEBHOOK_SECRET:-}"

body="$(python3 - "$REPO" "$BRANCH" "$SHA" "$MESSAGE" <<'PY'
import json, sys
repo, branch, sha, message = sys.argv[1:5]
print(json.dumps({"ref":f"refs/heads/{branch}","repository":{"full_name":repo},
  "head_commit":{"id":sha,"message":message,"author":{"name":"demo-dev"},
  "url":f"https://github.com/{repo}/commit/{sha}"}}))
PY
)"
args=(-s -X POST "$CM_URL/webhooks/github" -H 'content-type: application/json' -H 'x-github-event: push')
if [[ -n "$SECRET" ]]; then
  sig="sha256=$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$SECRET" -r | cut -d' ' -f1)"
  args+=(-H "x-hub-signature-256: $sig")
fi
curl "${args[@]}" --data "$body"
echo

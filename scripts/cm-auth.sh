#!/usr/bin/env bash
# Shared login helper. Works with auth enabled or disabled; exports CM_COOKIE
# and CM_CSRF for the other scripts.
set -euo pipefail

CM_URL="${CM_URL:-http://localhost:8080}"
CM_COOKIE="$(mktemp)"
CM_CSRF=""

cm_login() {
  local me login
  me="$(curl -s -c "$CM_COOKIE" "$CM_URL/auth/me")"
  CM_CSRF="$(printf '%s' "$me" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("csrf_token") or "")' 2>/dev/null || true)"
  if printf '%s' "$me" | grep -q '"auth_enabled":true' && ! printf '%s' "$me" | grep -q '"authenticated":true'; then
    : "${ADMIN_EMAIL:?set ADMIN_EMAIL when auth is enabled}"
    : "${ADMIN_PASSWORD:?set ADMIN_PASSWORD when auth is enabled}"
    login="$(curl -s -b "$CM_COOKIE" -c "$CM_COOKIE" -X POST "$CM_URL/auth/login" \
      -H 'content-type: application/json' \
      -d "$(python3 -c 'import json,os; print(json.dumps({"email":os.environ["ADMIN_EMAIL"],"password":os.environ["ADMIN_PASSWORD"]}))')")"
    CM_CSRF="$(printf '%s' "$login" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("csrf_token") or "")')"
  fi
}

cm_api() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-s -b "$CM_COOKIE" -X "$method")
  [[ -n "$CM_CSRF" ]] && args+=(-H "X-CSRF-Token: $CM_CSRF")
  if [[ -n "$data" ]]; then args+=(-H 'content-type: application/json' --data "$data"); fi
  curl "${args[@]}" "$CM_URL$path"
}

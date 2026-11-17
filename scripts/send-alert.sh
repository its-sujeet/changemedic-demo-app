#!/usr/bin/env bash
# Fire the same Alertmanager payload a Prometheus rule would send.
set -euo pipefail
source "$(dirname "$0")/cm-auth.sh"
SERVICE="${SERVICE:-checkout-api}"
NAMESPACE="${NAMESPACE:-demo}"
FINGERPRINT="${FINGERPRINT:-$(date -u +%Y%m%d%H%M%S)}"
ALERTNAME="${ALERTNAME:-HighErrorRate}"
SEVERITY="${SEVERITY:-critical}"
SUMMARY="${SUMMARY:-More than 20% of requests are failing on $SERVICE}"

payload="$(python3 - "$SERVICE" "$NAMESPACE" "$ALERTNAME" "$SEVERITY" "$SUMMARY" "$FINGERPRINT" <<'PYEOF'
import json, sys
service, ns, name, severity, summary, fingerprint = sys.argv[1:7]
print(json.dumps({"version":"4","status":"firing","alerts":[{
  "status":"firing","labels":{"alertname":name,"severity":severity,"service":service,"namespace":ns},
  "annotations":{"summary":summary},"fingerprint":fingerprint}]}))
PYEOF
)"
echo "==> alert $ALERTNAME for $SERVICE/$NAMESPACE"
cm_api POST /webhooks/alertmanager "$payload"
echo

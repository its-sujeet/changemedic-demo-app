# ChangeMedic demo app — test the whole loop against a real HTTP service

This is a small, intentionally faultable `checkout-api` plus an onboarding kit.
It exists so you can point **ChangeMedic** at a *real* workload — one with a Helm
release, Prometheus metrics, a GitHub repo and a deploy pipeline — and watch the
full loop: push → commit recorded → deploy reported → probe → alert → capsule →
reproduction → verified fix.

Nothing here is magic: the contract with ChangeMedic is three things, and they
work for **any** real app.

1. a **probe** (method, path, body, what status counts as failure),
2. an **alert** labelled `service`, `namespace`, `alertname`,
3. a **deploy event** carrying the Helm revision, image and commit SHA.

Replace this app with yours and keep those three.

## Layout

| Path | What |
|---|---|
| `app/` | FastAPI service: `/healthz`, `/readyz`, `/version`, `/charge`, `/metrics` |
| `charts/checkout-api/` | Helm chart with failure injection (`failRate`, `latencyMs`, `ready`) |
| `.github/workflows/deploy.yml` | Build → push GHCR → `helm upgrade` → `POST /webhooks/deploy` |
| `scripts/onboard.sh` | Register the project + probe, optionally connect the GitHub repo |
| `scripts/probe.sh` | Replay the endpoint and count status codes |
| `scripts/send-alert.sh` | Fire an Alertmanager payload |
| `scripts/send-push.sh` | Send a signed GitHub push without GitHub reaching your laptop |
| `scripts/e2e.sh` | Run the loop and print the incident/report/archive URLs |

## 1. Run and deploy the app

```bash
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
pytest -q

uvicorn app.main:app --port 8001 &
APP_URL=http://localhost:8001 ./scripts/probe.sh
```

On a cluster with ChangeMedic already installed:

```bash
helm upgrade --install checkout-api charts/checkout-api -n demo --create-namespace
kubectl -n demo port-forward svc/checkout-api 8001:80
```

## 2. Onboard it to ChangeMedic

```bash
export CM_URL=http://localhost:8080
# If ChangeMedic auth is enabled:
export ADMIN_EMAIL=admin@changemedic.local ADMIN_PASSWORD='...'

PROJECT=checkout-api-demo SERVICE=checkout-api NAMESPACE=demo \
  REPO=its-sujeet/changemedic-demo-app \
  GITHUB_TOKEN=ghp_... WEBHOOK_SECRET=s3cret \
  ./scripts/onboard.sh
```

For a trusted single-user install, `ADMIN_EMAIL`/`ADMIN_PASSWORD` are not needed.
Open the console at `$CM_URL/#/projects/checkout-api-demo`: **Get set up** shows
the three steps, **Right now** replays `/charge` every 5 s, and **Commit history**
records pushes with linked deploys and incidents.

## 3. Break it like the real world

The interesting failures leave the pods Ready and only traffic tells the truth:

```bash
# 100% of charges return 500, pods stay Ready
helm upgrade checkout-api charts/checkout-api -n demo --reuse-values --set failRate=1
APP_URL=http://localhost:8001 ./scripts/probe.sh     # failed=20 of 20
./scripts/send-alert.sh                              # alert labelled service/namespace
./scripts/e2e.sh                                     # incident + capsule + report URLs
```

Then open the printed incident URL. Stages 2, 6 and 8 replay the **same**
`/charge` probe, so "before" and "after" are comparable. Approve the proposed
rollback in the console, and stage 8 must see 0% errors before the incident is
resolved. The Markdown report and `capsule.tar.gz` are linked from the incident.

Restore health with `--set failRate=0` and report the healed release:

```bash
helm upgrade checkout-api charts/checkout-api -n demo --reuse-values --set failRate=0
curl -s -X POST "$CM_URL/webhooks/deploy" -H 'content-type: application/json' \
  -d '{"project":"checkout-api-demo","service":"checkout-api","namespace":"demo",
       "image":"ghcr.io/its-sujeet/changemedic-demo-app:1.0.0",
       "helm_revision":3,"status":"restored","deployed_by":"demo"}'
```

## 4. Test *your* real app instead

Point the three contracts at your service:

```bash
PROJECT=my-api SERVICE=my-api NAMESPACE=production \
  PROBE_METHOD=GET PROBE_PATH=/healthz REQUESTS=20 EXPECT_BELOW=400 \
  APP_URL=https://my-api.internal ./scripts/probe.sh

SERVICE=my-api NAMESPACE=production ALERTNAME=HighErrorRate \
  ./scripts/send-alert.sh
```

`onboard.sh` accepts the same variables and writes the project's probe and
repository connection. If your app exports `http_requests_total` and
`http_request_duration_seconds` on `/metrics`, ChangeMedic can also read
Prometheus instead of replaying traffic (`CM_METRICS_SOURCE=prometheus`).
Otherwise the bounded probe is the measurement, by design.

## GitHub Actions setup

Repository secrets/vars used by `.github/workflows/deploy.yml`:

- `KUBE_CONFIG` — base64 of a kubeconfig with permission to deploy in the target namespace.
- `CM_URL` — base URL of the ChangeMedic API.
- `CM_NAMESPACE` (var, default `demo`).
- `CM_PROJECT` (optional, default `checkout-api-demo`).

Every push to `main` then builds the image, deploys it and reports the release to
ChangeMedic through `/webhooks/deploy`. The GitHub webhook is separate: it records
the commit and can start this same workflow with `workflow_dispatch`.

Deploy is activated by ChangeMedic on push (workflow_dispatch). Live demo on EC2 k3s.

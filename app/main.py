"""A small, intentionally faultable service for ChangeMedic demos.

It exists so a developer can point ChangeMedic at a *real* HTTP workload: one
that exports Prometheus metrics, has a Helm release behind it, and can be made
to fail in ways that leave the pods Ready. Anything in this app can be replaced
by your own service — the probe, the alert labels and the deploy webhook are the
contract, not the Python code.
"""

from __future__ import annotations

import logging
import os
import random
import time

from fastapi import FastAPI, HTTPException
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from starlette.responses import Response

log = logging.getLogger("checkout-api")
app = FastAPI(title="checkout-api", version=os.getenv("APP_VERSION", "1.0.0"))

REQUESTS = Counter(
    "http_requests_total", "HTTP requests", ["endpoint", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds", "Request duration", ["endpoint"]
)


def env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError:
        return default


@app.middleware("http")
async def observe(request, call_next):
    started = time.perf_counter()
    response = await call_next(request)
    label = request.url.path
    REQUESTS.labels(label, str(response.status_code)).inc()
    LATENCY.labels(label).observe(time.perf_counter() - started)
    return response


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    if os.getenv("READY", "true").lower() == "false":
        raise HTTPException(status_code=503, detail="not ready")
    return {"status": "ready"}


@app.get("/version")
def version():
    return {"version": os.getenv("APP_VERSION", "1.0.0")}


@app.post("/charge")
def charge(body: dict):
    """The endpoint the demo probe replays. Failure is injected, not accidental."""
    delay = env_float("LATENCY_MS", 0) / 1000
    if delay:
        time.sleep(delay)
    if random.random() < env_float("FAIL_RATE", 0):
        log.warning("injected failure for /charge")
        raise HTTPException(status_code=500, detail="payment gateway unavailable")
    amount = body.get("amount", 0)
    return {"ok": True, "amount": amount, "currency": "USD", "version": os.getenv("APP_VERSION", "1.0.0")}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

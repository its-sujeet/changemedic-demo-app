from fastapi.testclient import TestClient

from app.main import app


def test_health_and_ready():
    c = TestClient(app)
    assert c.get("/healthz").json() == {"status": "ok"}
    assert c.get("/readyz").status_code == 200


def test_charge_and_metrics(monkeypatch):
    c = TestClient(app)
    monkeypatch.setenv("FAIL_RATE", "0")
    r = c.post("/charge", json={"amount": 5000})
    assert r.status_code == 200
    assert r.json()["amount"] == 5000
    metrics = c.get("/metrics").text
    assert "http_requests_total" in metrics
    assert "http_request_duration_seconds" in metrics


def test_injected_failure(monkeypatch):
    c = TestClient(app)
    monkeypatch.setenv("FAIL_RATE", "1")
    assert c.post("/charge", json={"amount": 5000}).status_code == 500

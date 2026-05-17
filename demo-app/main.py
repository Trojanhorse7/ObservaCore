import time
import random
import os
from flask import Flask, jsonify, request, Response
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)
START_TIME = time.time()

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Request latency",
    ["endpoint"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
)
UPTIME = Gauge("app_uptime_seconds", "App uptime")

@app.before_request
def start_timer():
    request._start_time = time.time()

@app.after_request
def record_metrics(response):
    latency = time.time() - request._start_time
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.path,
        status=str(response.status_code)
    ).inc()
    REQUEST_LATENCY.labels(endpoint=request.path).observe(latency)
    UPTIME.set(time.time() - START_TIME)
    return response

@app.route("/")
def index():
    time.sleep(random.uniform(0.01, 0.1))
    return jsonify({"status": "ok", "service": "observability-demo"})

@app.route("/health")
def health():
    return jsonify({"status": "ok", "uptime": round(time.time() - START_TIME, 2)})

@app.route("/slow")
def slow():
    time.sleep(random.uniform(0.5, 2.0))
    return jsonify({"status": "ok", "message": "slow response"})

@app.route("/error")
def error():
    if random.random() > 0.5:
        return jsonify({"error": "simulated error"}), 500
    return jsonify({"status": "ok"})

@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

import time
import random
import os
import logging

from flask import Flask, jsonify, request, Response
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

# OpenTelemetry — tracing
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION
from opentelemetry.instrumentation.flask import FlaskInstrumentor

# OpenTelemetry — logging (structured JSON with traceID injection)
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
from opentelemetry._logs import set_logger_provider
from opentelemetry.instrumentation.logging import LoggingInstrumentor

# ---------------------------------------------------------------------------
# Resource: identifies this service in Tempo and Loki
# ---------------------------------------------------------------------------
resource = Resource.create({
    SERVICE_NAME: "observability-demo",
    SERVICE_VERSION: "1.0.0",
    "deployment.environment": "production",
})

# ---------------------------------------------------------------------------
# Tracing setup — export spans to OTel Collector → Tempo
# ---------------------------------------------------------------------------
OTEL_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")

trace_provider = TracerProvider(resource=resource)
trace_provider.add_span_processor(
    BatchSpanProcessor(
        OTLPSpanExporter(endpoint=OTEL_ENDPOINT, insecure=True)
    )
)
trace.set_tracer_provider(trace_provider)
tracer = trace.get_tracer("observability-demo")

# ---------------------------------------------------------------------------
# Logging setup — structured JSON with trace_id injected so Loki logs are
# clickable in Grafana (derived field: traceID=<hex>)
# ---------------------------------------------------------------------------
log_provider = LoggerProvider(resource=resource)
log_provider.add_log_record_processor(
    BatchLogRecordProcessor(
        OTLPLogExporter(endpoint=OTEL_ENDPOINT, insecure=True)
    )
)
set_logger_provider(log_provider)

LoggingInstrumentor().instrument(set_logging_format=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s level=%(levelname)s service=observability-demo traceID=%(otelTraceID)s spanID=%(otelSpanID)s %(message)s",
)
logger = logging.getLogger("observability-demo")

# ---------------------------------------------------------------------------
# Flask app
# ---------------------------------------------------------------------------
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

START_TIME = time.time()

# ---------------------------------------------------------------------------
# Prometheus metrics
# ---------------------------------------------------------------------------
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Request latency in seconds",
    ["endpoint"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
)
UPTIME = Gauge("app_uptime_seconds", "Seconds since app start")


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


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route("/")
def index():
    with tracer.start_as_current_span("handle-index") as span:
        sleep_ms = random.uniform(0.01, 0.1)
        span.set_attribute("sleep_seconds", sleep_ms)
        time.sleep(sleep_ms)
        logger.info("Handled index request", extra={"endpoint": "/"})
        return jsonify({"status": "ok", "service": "observability-demo"})


@app.route("/health")
def health():
    with tracer.start_as_current_span("handle-health"):
        uptime = round(time.time() - START_TIME, 2)
        logger.info("Health check", extra={"uptime": uptime})
        return jsonify({"status": "ok", "uptime": uptime})


@app.route("/slow")
def slow():
    with tracer.start_as_current_span("handle-slow") as span:
        sleep_s = random.uniform(0.5, 2.0)
        span.set_attribute("sleep_seconds", sleep_s)
        span.set_attribute("simulated_latency", True)
        logger.warning("Slow response served", extra={"sleep_seconds": sleep_s, "endpoint": "/slow"})
        time.sleep(sleep_s)
        return jsonify({"status": "ok", "message": "slow response", "sleep_seconds": round(sleep_s, 3)})


@app.route("/error")
def error():
    with tracer.start_as_current_span("handle-error") as span:
        if random.random() > 0.5:
            span.set_attribute("error", True)
            span.set_attribute("http.status_code", 500)
            logger.error("Simulated 500 error", extra={"endpoint": "/error"})
            return jsonify({"error": "simulated error"}), 500
        logger.info("Error endpoint returned 200", extra={"endpoint": "/error"})
        return jsonify({"status": "ok"})


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    logger.info("Starting observability-demo on port 8080")
    app.run(host="0.0.0.0", port=8080)

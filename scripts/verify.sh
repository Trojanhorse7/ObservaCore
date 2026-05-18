#!/usr/bin/env bash
set -euo pipefail

echo "============================================"
echo "  Observability Platform — Verify"
echo "============================================"

PASS=0; FAIL=0

check() {
    local name="$1" port="$2" path="${3:-/}"
    if systemctl is-active --quiet "$name" 2>/dev/null; then
        echo "  ✓ $name is active"
        PASS=$((PASS+1))
    else
        echo "  ✗ $name is NOT active"
        FAIL=$((FAIL+1))
    fi
    if [ -n "$port" ]; then
        if curl -sf "http://localhost:${port}${path}" > /dev/null 2>&1; then
            echo "  ✓ localhost:${port}${path} responding"
            PASS=$((PASS+1))
        else
            echo "  ✗ localhost:${port}${path} NOT responding"
            FAIL=$((FAIL+1))
        fi
    fi
}

echo ""
check "prometheus"        "9090" "/-/healthy"
check "node_exporter"     "9100" "/metrics"
check "blackbox_exporter" "9115" "/metrics"
check "alertmanager"      "9093" "/-/healthy"
check "loki"              "3100" "/ready"
check "tempo"             "3200" "/ready"
check "grafana-server"    "3000" "/api/health"
check "otelcol"           ""

echo ""
echo "Passed: $PASS  Failed: $FAIL"

PUBLIC_IP=$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null \
    || hostname -I | awk '{print $1}')
echo ""
echo "Grafana:      http://${PUBLIC_IP}:3000"
echo "Prometheus:   http://${PUBLIC_IP}:9090"
echo "Alertmanager: http://${PUBLIC_IP}:9093"

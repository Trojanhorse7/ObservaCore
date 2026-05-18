#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/home/ubuntu/ObservaCore"
LOG_FILE="/var/log/observability-install.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Starting installation from $REPO_DIR"

# ── Kill anything holding apt locks ──────────────────────────────────────────
log "Preparing apt..."
systemctl stop unattended-upgrades 2>/dev/null || true
systemctl disable unattended-upgrades 2>/dev/null || true
killall apt apt-get unattended-upgrade 2>/dev/null || true
sleep 3
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
      /var/cache/apt/archives/lock /var/lib/apt/lists/lock
dpkg --configure -a 2>/dev/null || true

# ── Base dependencies ─────────────────────────────────────────────────────────
log "Installing dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget unzip tar git python3 python3-pip python3-venv \
    jq net-tools apt-transport-https software-properties-common

# ── Create users ──────────────────────────────────────────────────────────────
for user in prometheus alertmanager loki tempo otel node_exporter blackbox; do
    id "$user" &>/dev/null || useradd --no-create-home --shell /bin/false "$user"
    log "User ready: $user"
done

# ── Create directories ────────────────────────────────────────────────────────
mkdir -p /var/lib/{prometheus,alertmanager,loki,tempo}
mkdir -p /var/lib/tempo/{blocks,wal}
mkdir -p /etc/{prometheus/rules,alertmanager/templates,loki,tempo,otel,blackbox}
mkdir -p /var/log/observability

chown prometheus:prometheus /var/lib/prometheus /etc/prometheus
chown alertmanager:alertmanager /var/lib/alertmanager /etc/alertmanager
chown loki:loki /var/lib/loki /etc/loki
chown tempo:tempo /var/lib/tempo /etc/tempo

# ── Helper: download with retry ───────────────────────────────────────────────
download() {
    local url=$1 dest=$2
    for attempt in 1 2 3; do
        wget -q --timeout=60 --tries=3 -O "$dest" "$url" && return 0
        log "Download attempt $attempt failed for $url, retrying..."
        sleep 5
    done
    log "ERROR: Failed to download $url after 3 attempts"
    exit 1
}

# ── Skip already-installed binaries ──────────────────────────────────────────
install_binary() {
    local name="$1"
    local path="/usr/local/bin/${name}"
    if [ -x "$path" ]; then
        log "$name already installed, skipping download"
        return 0
    fi
    return 1
}

# ── Prometheus ────────────────────────────────────────────────────────────────
PROMETHEUS_VERSION="2.51.2"
if ! install_binary prometheus; then
    log "Installing Prometheus ${PROMETHEUS_VERSION}..."
    cd /tmp
    download "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" \
        "prometheus.tar.gz"
    tar -xzf prometheus.tar.gz
    cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /usr/local/bin/
    cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /usr/local/bin/
    cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles" /etc/prometheus/
    cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries" /etc/prometheus/
    chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
fi

cp "$REPO_DIR/prometheus/prometheus.yml" /etc/prometheus/prometheus.yml
cp "$REPO_DIR/prometheus/rules/"*.yml /etc/prometheus/rules/
chown -R prometheus:prometheus /etc/prometheus

cat > /etc/systemd/system/prometheus.service << 'UNIT'
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus \
    --storage.tsdb.retention.time=30d \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090 \
    --web.enable-remote-write-receiver \
    --enable-feature=exemplar-storage

[Install]
WantedBy=multi-user.target
UNIT
log "Prometheus configured"

# ── Node Exporter ─────────────────────────────────────────────────────────────
NODE_VERSION="1.7.0"
if ! install_binary node_exporter; then
    log "Installing Node Exporter ${NODE_VERSION}..."
    cd /tmp
    download "https://github.com/prometheus/node_exporter/releases/download/v${NODE_VERSION}/node_exporter-${NODE_VERSION}.linux-amd64.tar.gz" \
        "node_exporter.tar.gz"
    tar -xzf node_exporter.tar.gz
    cp "node_exporter-${NODE_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
    chown node_exporter:node_exporter /usr/local/bin/node_exporter
fi

cat > /etc/systemd/system/node_exporter.service << 'UNIT'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100

[Install]
WantedBy=multi-user.target
UNIT
log "Node Exporter configured"

# ── Blackbox Exporter ─────────────────────────────────────────────────────────
BLACKBOX_VERSION="0.24.0"
if ! install_binary blackbox_exporter; then
    log "Installing Blackbox Exporter ${BLACKBOX_VERSION}..."
    cd /tmp
    download "https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_VERSION}/blackbox_exporter-${BLACKBOX_VERSION}.linux-amd64.tar.gz" \
        "blackbox_exporter.tar.gz"
    tar -xzf blackbox_exporter.tar.gz
    cp "blackbox_exporter-${BLACKBOX_VERSION}.linux-amd64/blackbox_exporter" /usr/local/bin/
    chown blackbox:blackbox /usr/local/bin/blackbox_exporter
fi

cat > /etc/blackbox/blackbox.yml << 'CONFIG'
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: []
      method: GET
      follow_redirects: true
      preferred_ip_protocol: "ip4"
CONFIG

cat > /etc/systemd/system/blackbox_exporter.service << 'UNIT'
[Unit]
Description=Blackbox Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=blackbox
Group=blackbox
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/blackbox_exporter \
    --config.file=/etc/blackbox/blackbox.yml \
    --web.listen-address=0.0.0.0:9115

[Install]
WantedBy=multi-user.target
UNIT
log "Blackbox Exporter configured"

# ── Alertmanager ──────────────────────────────────────────────────────────────
ALERTMANAGER_VERSION="0.27.0"
if ! install_binary alertmanager; then
    log "Installing Alertmanager ${ALERTMANAGER_VERSION}..."
    cd /tmp
    download "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz" \
        "alertmanager.tar.gz"
    tar -xzf alertmanager.tar.gz
    cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" /usr/local/bin/
    cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool" /usr/local/bin/
    chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool
fi

cp "$REPO_DIR/alertmanager/alertmanager.yml" /etc/alertmanager/
cp "$REPO_DIR/alertmanager/templates/"*.tmpl /etc/alertmanager/templates/

# Inject the Slack webhook URL from the environment into the deployed config
# The source file keeps 'replace this' as a placeholder (never commit real URLs)
if [ -n "${SLACK_WEBHOOK_URL}" ] && [ "${SLACK_WEBHOOK_URL}" != "replace this" ]; then
    sed -i "s|slack_api_url: 'replace this'|slack_api_url: '${SLACK_WEBHOOK_URL}'|" \
        /etc/alertmanager/alertmanager.yml
    log "Slack webhook URL injected into alertmanager.yml"
else
    log "WARNING: SLACK_WEBHOOK_URL not set — alertmanager.yml still has placeholder. Alerts will not fire."
fi

chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

cat > /etc/systemd/system/alertmanager.service << 'UNIT'
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/alertmanager \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/var/lib/alertmanager \
    --web.listen-address=0.0.0.0:9093

[Install]
WantedBy=multi-user.target
UNIT
log "Alertmanager configured"

# ── Loki ──────────────────────────────────────────────────────────────────────
LOKI_VERSION="2.9.6"
if ! install_binary loki; then
    log "Installing Loki ${LOKI_VERSION}..."
    cd /tmp
    download "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip" \
        "loki.zip"
    unzip -q -o loki.zip
    cp loki-linux-amd64 /usr/local/bin/loki
    chmod +x /usr/local/bin/loki
    chown loki:loki /usr/local/bin/loki
fi

cp "$REPO_DIR/loki/loki-config.yml" /etc/loki/
chown -R loki:loki /etc/loki /var/lib/loki

cat > /etc/systemd/system/loki.service << 'UNIT'
[Unit]
Description=Loki Log Aggregator
Wants=network-online.target
After=network-online.target

[Service]
User=loki
Group=loki
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yml

[Install]
WantedBy=multi-user.target
UNIT
log "Loki configured"

# ── Tempo ─────────────────────────────────────────────────────────────────────
TEMPO_VERSION="2.4.1"
if ! install_binary tempo; then
    log "Installing Tempo ${TEMPO_VERSION}..."
    cd /tmp
    download "https://github.com/grafana/tempo/releases/download/v${TEMPO_VERSION}/tempo_${TEMPO_VERSION}_linux_amd64.tar.gz" \
        "tempo.tar.gz"
    tar -xzf tempo.tar.gz
    cp tempo /usr/local/bin/
    chmod +x /usr/local/bin/tempo
    chown tempo:tempo /usr/local/bin/tempo
fi

cp "$REPO_DIR/tempo/tempo-config.yml" /etc/tempo/
chown -R tempo:tempo /etc/tempo /var/lib/tempo

cat > /etc/systemd/system/tempo.service << 'UNIT'
[Unit]
Description=Tempo Distributed Tracing
Wants=network-online.target
After=network-online.target

[Service]
User=tempo
Group=tempo
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/tempo -config.file=/etc/tempo/tempo-config.yml

[Install]
WantedBy=multi-user.target
UNIT
log "Tempo configured"

# ── Grafana ───────────────────────────────────────────────────────────────────
if ! command -v grafana-server &>/dev/null; then
    log "Installing Grafana..."
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" \
        > /etc/apt/sources.list.d/grafana.list
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y grafana
fi

mkdir -p /etc/grafana/provisioning/{datasources,dashboards}
mkdir -p /var/lib/grafana/dashboards

cp "$REPO_DIR/grafana/provisioning/datasources/"*.yml /etc/grafana/provisioning/datasources/
cp "$REPO_DIR/grafana/provisioning/dashboards/"*.yml  /etc/grafana/provisioning/dashboards/
cp "$REPO_DIR/grafana/dashboards/"*.json              /var/lib/grafana/dashboards/
chown -R grafana:grafana /etc/grafana/provisioning /var/lib/grafana/dashboards

GRAFANA_PASS="${GRAFANA_ADMIN_PASSWORD:-admin}"
# Match both commented (;admin_password) and already-uncommented (admin_password) forms
# so re-runs and upgrades always apply the correct password
sed -i "s/^;*admin_password = .*/admin_password = ${GRAFANA_PASS}/" /etc/grafana/grafana.ini
sed -i 's/^;*admin_user = .*/admin_user = admin/'                   /etc/grafana/grafana.ini
log "Grafana admin password set (use GRAFANA_ADMIN_PASSWORD env var to override)"
log "Grafana configured"

# ── Pushgateway ───────────────────────────────────────────────────────────────
# Required for DORA metrics pushed from GitHub Actions
PUSHGATEWAY_VERSION="1.8.0"
if ! install_binary pushgateway; then
    log "Installing Pushgateway ${PUSHGATEWAY_VERSION}..."
    cd /tmp
    download "https://github.com/prometheus/pushgateway/releases/download/v${PUSHGATEWAY_VERSION}/pushgateway-${PUSHGATEWAY_VERSION}.linux-amd64.tar.gz" \
        "pushgateway.tar.gz"
    tar -xzf pushgateway.tar.gz
    cp "pushgateway-${PUSHGATEWAY_VERSION}.linux-amd64/pushgateway" /usr/local/bin/
    chown prometheus:prometheus /usr/local/bin/pushgateway
fi

cat > /etc/systemd/system/pushgateway.service << 'UNIT'
[Unit]
Description=Prometheus Pushgateway
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/pushgateway \
    --web.listen-address=0.0.0.0:9091 \
    --persistence.file=/var/lib/prometheus/pushgateway.db \
    --persistence.interval=5m

[Install]
WantedBy=multi-user.target
UNIT
log "Pushgateway configured"

# ── Demo App ──────────────────────────────────────────────────────────────────
# Instrumented Flask app — emits Prometheus metrics and OTel traces
if ! command -v python3 &>/dev/null; then
    log "ERROR: python3 not found"
    exit 1
fi

log "Installing demo app dependencies..."

# python3-setuptools provides pkg_resources at the system level.
# On Ubuntu 24.04 (Python 3.12), venvs do not bundle setuptools, so
# opentelemetry-instrumentation 0.45b0 crashes on import without it.
# Installing via apt and using --system-site-packages is more reliable
# than pip install setuptools inside a venv on Noble.
DEBIAN_FRONTEND=noninteractive apt-get install -y python3-setuptools python3-pkg-resources

mkdir -p /opt/demo-app
cp "$REPO_DIR/demo-app/main.py"          /opt/demo-app/
cp "$REPO_DIR/demo-app/requirements.txt" /opt/demo-app/

# Recreate the venv cleanly with system-site-packages so setuptools
# (and therefore pkg_resources) is visible inside the venv
rm -rf /opt/demo-app/venv
python3 -m venv --system-site-packages /opt/demo-app/venv

/opt/demo-app/venv/bin/python -m pip install --quiet --upgrade pip
/opt/demo-app/venv/bin/python -m pip install --quiet -r /opt/demo-app/requirements.txt

id demo-app &>/dev/null || useradd --no-create-home --shell /bin/false demo-app
chown -R demo-app:demo-app /opt/demo-app

cat > /etc/systemd/system/demo-app.service << 'UNIT'
[Unit]
Description=ObservaCore Demo App
Wants=network-online.target otelcol.service
After=network-online.target otelcol.service

[Service]
User=demo-app
Group=demo-app
Type=simple
Restart=always
RestartSec=5s
WorkingDirectory=/opt/demo-app
Environment=OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
ExecStart=/opt/demo-app/venv/bin/python main.py

[Install]
WantedBy=multi-user.target
UNIT
log "Demo app configured"

# ── OTel Collector ────────────────────────────────────────────────────────────
OTEL_VERSION="0.97.0"
if ! install_binary otelcol; then
    log "Installing OTel Collector ${OTEL_VERSION}..."
    cd /tmp
    download "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_linux_amd64.tar.gz" \
        "otelcol.tar.gz"
    tar -xzf otelcol.tar.gz
    cp otelcol-contrib /usr/local/bin/otelcol
    chmod +x /usr/local/bin/otelcol
    chown otel:otel /usr/local/bin/otelcol
fi

cp "$REPO_DIR/otel-collector/otel-collector-config.yml" /etc/otel/
chown -R otel:otel /etc/otel

cat > /etc/systemd/system/otelcol.service << 'UNIT'
[Unit]
Description=OpenTelemetry Collector
Wants=network-online.target
After=network-online.target

[Service]
User=otel
Group=otel
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/otelcol --config=/etc/otel/otel-collector-config.yml

[Install]
WantedBy=multi-user.target
UNIT
log "OTel Collector configured"

# ── Enable and start all services ─────────────────────────────────────────────
log "Starting all services..."
systemctl daemon-reload

SERVICES="prometheus node_exporter blackbox_exporter alertmanager loki tempo grafana-server otelcol pushgateway demo-app"

for svc in $SERVICES; do
    systemctl enable "$svc"
    systemctl restart "$svc"
    sleep 2
    if systemctl is-active --quiet "$svc"; then
        log "✓ $svc running"
    else
        log "✗ $svc FAILED"
        journalctl -u "$svc" -n 20 --no-pager | tee -a "$LOG_FILE"
    fi
done

# ── Force Grafana admin password via CLI (works on re-runs and existing DBs) ──
# Stop Grafana first to release the DB lock, reset, then restart
log "Setting Grafana admin password via grafana-cli..."
systemctl stop grafana-server
sleep 2
GRAFANA_BIN=$(command -v grafana || echo "/usr/bin/grafana")
CLI_OUTPUT=$(cd /usr/share/grafana && "${GRAFANA_BIN}" cli admin reset-admin-password "${GRAFANA_PASS}" \
    --config /etc/grafana/grafana.ini 2>&1)
CLI_EXIT=$?
log "grafana cli output: ${CLI_OUTPUT}"
if [ $CLI_EXIT -eq 0 ]; then
    log "Grafana admin password confirmed: admin/${GRAFANA_PASS}"
else
    log "WARNING: grafana cli reset failed (exit ${CLI_EXIT})"
fi
systemctl start grafana-server
sleep 3

# Use SERVER_HOST from Terraform as the authoritative public IP.
# Falls back to EC2 metadata, then checkip, then private IP (logs a warning).
if [ -n "${SERVER_HOST}" ]; then
    PUBLIC_IP="${SERVER_HOST}"
    log "Using SERVER_HOST for public IP: ${PUBLIC_IP}"
else
    PUBLIC_IP=$(curl -sf --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    if [ -z "${PUBLIC_IP}" ]; then
        PUBLIC_IP=$(curl -sf --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')
    fi
    if [ -z "${PUBLIC_IP}" ]; then
        log "WARNING: Could not resolve public IP — alert dashboard links will use private IP. Set server_host in terraform.tfvars."
        PUBLIC_IP=$(hostname -I | awk '{print $1}')
    fi
fi

# ── Patch dashboard_url in deployed configs with the real public IP ───────────
# Source files keep localhost (portable); only the deployed copies are patched.
GRAFANA_URL="http://${PUBLIC_IP}:3000"
log "Patching dashboard URLs to ${GRAFANA_URL}..."
for f in /etc/prometheus/rules/*.yml /etc/alertmanager/alertmanager.yml; do
    sed -i "s|http://localhost:3000|${GRAFANA_URL}|g" "$f"
done
systemctl reload prometheus alertmanager 2>/dev/null || true
log "Dashboard URLs patched"

log "======================================"
log "Installation complete"
log "Grafana:      http://${PUBLIC_IP}:3000  (admin/${GRAFANA_PASS})"
log "Prometheus:   http://${PUBLIC_IP}:9090"
log "Alertmanager: http://${PUBLIC_IP}:9093"
log "Loki:         http://${PUBLIC_IP}:3100"
log "Tempo:        http://${PUBLIC_IP}:3200"
log "======================================"

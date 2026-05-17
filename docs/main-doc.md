# Production-Grade Observability Platform
## LGTM Stack · DORA Metrics · SLOs · Incident Management

> **Team:** Pabby & Trojan  
> **Track:** DevOps — Stage 6  
> **Stack:** Loki · Grafana · Tempo · Prometheus (LGTP)

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture & Data Flow](#2-architecture--data-flow)
3. [Repository Structure](#3-repository-structure)
4. [One-Command Deployment](#4-one-command-deployment)
5. [Part 1 — Deploy & Harden the Full LGTM Stack](#5-part-1--deploy--harden-the-full-lgtm-stack)
6. [Part 2 — Four Golden Signals as SLIs](#6-part-2--four-golden-signals-as-slis)
7. [Part 3 — SLOs & Error Budgets](#7-part-3--slos--error-budgets)
8. [Part 4 — DORA Metrics & CI/CD Observability](#8-part-4--dora-metrics--cicd-observability)
9. [Part 5 — Grafana Dashboards](#9-part-5--grafana-dashboards)
10. [Part 6 — Alerting System](#10-part-6--alerting-system)
11. [Part 7 — Incident Management & Runbooks](#11-part-7--incident-management--runbooks)
12. [Part 8 — Game Day: Chaos & Failure Simulation](#12-part-8--game-day-chaos--failure-simulation)
13. [Error Budget Policy](#13-error-budget-policy)
14. [Toil Identification & Automation](#14-toil-identification--automation)
15. [Technology Choices & Philosophy](#15-technology-choices--philosophy)

---

## 1. Project Overview

This platform delivers **production-grade observability** by going beyond simple up/down monitoring into **user-centric reliability engineering**. The platform enables any engineering team to:

- **Observe** — Unified metrics, logs, and traces in a single pane of glass (Grafana).
- **Measure** — Quantify reliability through SLI/SLO/Error Budget frameworks.
- **Act** — Alert on burn rates, not just thresholds, reducing alert fatigue.
- **Improve** — Track DORA metrics to connect engineering habits to business outcomes.
- **Recover** — Runbooks and structured incident reviews for every failure scenario.

### Why LGTP Over Managed Alternatives?

| Concern | LGTP Self-Hosted | Managed (Datadog, New Relic) |
|---|---|---|
| Cost at scale | Predictable infra cost | Per-seat / per-host pricing explodes |
| Data sovereignty | Full control | Vendor lock-in, data leaves your VPC |
| Customisation | Unlimited PromQL, LogQL | Feature-gated |
| Cardinality limits | None | Hard limits on high-cardinality labels |
| Correlation | Native Grafana linking | Requires premium tiers |
| IaC | Terraform providers exist | Partial API coverage |

---

## 2. Architecture & Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                                 │
│                                                                     │
│  ┌──────────────┐  ┌────────────────┐  ┌──────────────────────┐   │
│  │ Node Exporter│  │Blackbox Exporter│  │  Instrumented App    │   │
│  │ (system)     │  │ (HTTP probes)  │  │  (OpenTelemetry SDK) │   │
│  └──────┬───────┘  └───────┬────────┘  └──────────┬───────────┘   │
│         │                  │                       │               │
└─────────┼──────────────────┼───────────────────────┼───────────────┘
          │  scrape           │  scrape               │ OTLP push
          ▼                  ▼                       ▼
┌─────────────────┐                        ┌─────────────────────┐
│   PROMETHEUS    │                        │  OpenTelemetry      │
│   (metrics)     │                        │  Collector          │
│  :9090          │                        │  :4317 (gRPC)       │
└────────┬────────┘                        └────┬──────────┬─────┘
         │  remote_write (optional)             │ traces   │ logs
         │                                      ▼          ▼
         │                              ┌──────────┐  ┌──────────┐
         │                              │  TEMPO   │  │  LOKI    │
         │                              │ (traces) │  │  (logs)  │
         │                              │  :3200   │  │  :3100   │
         │                              └────┬─────┘  └────┬─────┘
         │                                   │              │
         └───────────────────────────────────┼──────────────┘
                                             ▼
                                    ┌─────────────────┐
                                    │    GRAFANA       │
                                    │  (unified UI)    │
                                    │  :3000           │
                                    └────────┬─────────┘
                                             │ alerts
                                             ▼
                                    ┌─────────────────┐
                                    │  ALERTMANAGER   │
                                    │  :9093          │
                                    └────────┬─────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │  Slack          │
                                    │  #DevOps-Alerts │
                                    └─────────────────┘
```

**Data Flow Summary:**

1. **Metrics** — Node Exporter and Blackbox Exporter expose `/metrics`. Prometheus scrapes them every 15 seconds. GitHub Actions writes deployment events via Pushgateway or webhook receiver.
2. **Logs** — Applications and systemd journals ship logs to the OpenTelemetry Collector (OTLP). The Collector forwards to Loki with structured labels.
3. **Traces** — Instrumented service sends OTLP spans to the Collector, which forwards to Tempo. Trace IDs are embedded in log lines for correlation.
4. **Dashboards** — Grafana queries all three backends. Derived fields in Loki link trace IDs directly to Tempo.
5. **Alerts** — Prometheus evaluates alert rules every 15s. Alertmanager routes to Slack with structured templates.

---

## 3. Repository Structure

```
observability-platform/
├── terraform/
│   ├── main.tf                     # Root module — composes all resources
│   ├── variables.tf
│   ├── outputs.tf
│   ├── modules/
│   │   ├── prometheus/             # Downloads binary, writes config, installs systemd unit
│   │   ├── loki/
│   │   ├── tempo/
│   │   ├── grafana/
│   │   ├── alertmanager/
│   │   ├── node-exporter/
│   │   ├── blackbox-exporter/
│   │   └── otel-collector/
│   └── terraform.tfvars.example
│
├── systemd/
│   ├── prometheus.service
│   ├── loki.service
│   ├── tempo.service
│   ├── grafana-server.service
│   ├── alertmanager.service
│   ├── node-exporter.service
│   ├── blackbox-exporter.service
│   └── otel-collector.service
│
├── scripts/
│   ├── install.sh                  # Bootstrap: creates users, directories, downloads binaries
│   └── verify.sh                   # Post-deploy health checks
│
├── prometheus/
│   ├── prometheus.yml              # Scrape configs + remote_write
│   ├── rules/
│   │   ├── infrastructure.yml      # CPU, memory, disk, host-down rules
│   │   ├── slo-burn-rate.yml       # Multi-window burn rate rules
│   │   └── cicd.yml                # CFR and MTTR alert rules
│   └── recording-rules.yml         # Pre-computed SLI ratios
│
├── alertmanager/
│   ├── alertmanager.yml            # Route tree + inhibition rules
│   └── templates/
│       └── slack.tmpl              # Structured Slack notification template
│
├── loki/
│   └── loki-config.yml
│
├── tempo/
│   └── tempo-config.yml
│
├── otel-collector/
│   └── otel-collector-config.yml
│
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yml     # Prometheus, Loki, Tempo auto-provisioned
│   │   └── dashboards/
│   │       └── dashboards.yml      # Dashboard provider config
│   └── dashboards/
│       ├── dora-metrics.json
│       ├── slo-error-budget.json
│       ├── node-exporter.json
│       ├── blackbox-exporter.json
│       └── unified-observability.json
│
├── runbooks/
│   ├── cpu-warning.md
│   ├── cpu-critical.md
│   ├── memory-warning.md
│   ├── memory-critical.md
│   ├── disk-warning.md
│   ├── disk-critical.md
│   ├── host-down.md
│   ├── slo-fast-burn.md
│   ├── slo-slow-burn.md
│   ├── cfr-threshold-exceeded.md
│   └── mttr-exceeded.md
│
├── slo/
│   ├── slo-definitions.yml         # Machine-readable SLO targets
│   └── error-budget-policy.md
│
├── incidents/
│   └── pir-001-latency-spike.md    # Post-Incident Review
│
├── game-day/
│   ├── scenario-1-deployment-failure.md
│   ├── scenario-2-latency-injection.md
│   └── scenario-3-resource-pressure.md
│
├── docs/
│   ├── main-doc.md                 # This file
│   ├── pabby-doc.md
│   └── trojan-doc.md
│
└── README.md
```

> There is no Docker or Docker Compose in this project. Every component runs as a native Linux binary managed by systemd. Terraform provisions, configures, and starts each service via `null_resource` + `local-exec` provisioners.

---

## 4. One-Command Deployment

The entire stack is provisioned with a single Terraform command. No Docker, no containers — all services run as native binaries under systemd.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set your server IP, Slack webhook URL, and target URLs
terraform init && terraform apply -auto-approve
```

That one command:
1. Creates a dedicated system user for each service (`prometheus`, `loki`, `grafana`, etc.).
2. Creates the required directories under `/etc/` and `/var/lib/`.
3. Downloads the correct binary version for each service.
4. Writes all configuration files from Terraform templates.
5. Installs and enables systemd unit files.
6. Starts every service and sets it to start on boot.

### Verification after deployment

```bash
# Quick health check — run after terraform apply
bash scripts/verify.sh
```

| Service | Check | Expected |
|---|---|---|
| Prometheus | `curl http://localhost:9090/-/healthy` | `Prometheus Server is Healthy.` |
| Grafana | `curl http://localhost:3000/api/health` | `{"database":"ok"}` |
| Alertmanager | `curl http://localhost:9093/-/healthy` | `OK` |
| Loki | `curl http://localhost:3100/ready` | `ready` |
| Tempo | `curl http://localhost:3200/ready` | `ready` |
| Node Exporter | `curl http://localhost:9100/metrics` | Metrics output |
| Blackbox Exporter | `curl http://localhost:9115` | Probe results page |
| OTel Collector | `systemctl is-active otel-collector` | `active` |

### Check all systemd services at once

```bash
systemctl status prometheus loki tempo grafana-server alertmanager \
  node-exporter blackbox-exporter otel-collector
```

---

## 5. Part 1 — Deploy & Harden the Full LGTM Stack

### 5.1 Component Versions, Ports & systemd Service Names

| Component | Version | Port | systemd Unit | Binary Location |
|---|---|---|---|---|
| Prometheus | 2.51+ | 9090 | `prometheus.service` | `/usr/local/bin/prometheus` |
| Loki | 3.0+ | 3100 | `loki.service` | `/usr/local/bin/loki` |
| Tempo | 2.4+ | 3200 | `tempo.service` | `/usr/local/bin/tempo` |
| Grafana | 10.4+ | 3000 | `grafana-server.service` | `/usr/sbin/grafana-server` |
| Alertmanager | 0.27+ | 9093 | `alertmanager.service` | `/usr/local/bin/alertmanager` |
| Node Exporter | 1.7+ | 9100 | `node-exporter.service` | `/usr/local/bin/node_exporter` |
| Blackbox Exporter | 0.24+ | 9115 | `blackbox-exporter.service` | `/usr/local/bin/blackbox_exporter` |
| OTel Collector | 0.97+ | 4317/4318 | `otel-collector.service` | `/usr/local/bin/otelcol-contrib` |

### 5.1a systemd Unit File Pattern

Every service follows the same unit file pattern. Automatic restart is enforced via `Restart=on-failure`.

```ini
# systemd/prometheus.service
[Unit]
Description=Prometheus Monitoring System
Documentation=https://prometheus.io/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=30d \
  --web.enable-lifecycle \
  --web.listen-address=0.0.0.0:9090
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

All other unit files follow this same structure, substituting the correct `User`, `ExecStart`, and flags.

### 5.1b Terraform Module Pattern

Each Terraform module uses `null_resource` + `local-exec` to install its service. All modules share the same structure:

```hcl
# terraform/modules/prometheus/main.tf
variable "version" { default = "2.51.2" }
variable "config_path" { default = "/etc/prometheus/prometheus.yml" }

resource "null_resource" "prometheus_install" {
  triggers = { version = var.version }

  provisioner "local-exec" {
    command = <<-EOT
      # Create system user
      useradd --no-create-home --shell /bin/false prometheus || true

      # Create directories
      mkdir -p /etc/prometheus /var/lib/prometheus
      chown prometheus:prometheus /var/lib/prometheus

      # Download and install binary
      cd /tmp
      wget -q https://github.com/prometheus/prometheus/releases/download/v${var.version}/prometheus-${var.version}.linux-amd64.tar.gz
      tar xzf prometheus-${var.version}.linux-amd64.tar.gz
      cp prometheus-${var.version}.linux-amd64/prometheus /usr/local/bin/
      cp prometheus-${var.version}.linux-amd64/promtool /usr/local/bin/
      chmod +x /usr/local/bin/prometheus /usr/local/bin/promtool
    EOT
  }
}

resource "local_file" "prometheus_config" {
  filename = var.config_path
  content  = templatefile("${path.module}/templates/prometheus.yml.tpl", {
    alertmanager_host = var.alertmanager_host
  })
  depends_on = [null_resource.prometheus_install]
}

resource "null_resource" "prometheus_service" {
  triggers = { config_hash = local_file.prometheus_config.content }

  provisioner "local-exec" {
    command = <<-EOT
      cp ${path.module}/files/prometheus.service /etc/systemd/system/
      systemctl daemon-reload
      systemctl enable prometheus
      systemctl restart prometheus
    EOT
  }

  depends_on = [local_file.prometheus_config]
}
```

### 5.2 Prometheus Scrape Configuration

```yaml
# prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'observability-platform'
    env: 'production'

rule_files:
  - /etc/prometheus/rules/*.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

scrape_configs:
  - job_name: 'node-exporter'
    scrape_interval: 15s
    static_configs:
      - targets: ['localhost:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

  - job_name: 'blackbox-http'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://yourapp.example.com
          - https://yourapp.example.com/health
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115

  - job_name: 'github-actions'
    static_configs:
      - targets: ['localhost:9091']
    honor_labels: true
```

### 5.3 Retention Periods

| Backend | Default Retention | Configuration |
|---|---|---|
| Prometheus | 30 days | `--storage.tsdb.retention.time=30d` |
| Loki | 30 days | `retention_period: 720h` in `loki-config.yml` |
| Tempo | 7 days | `max_block_duration: 168h` in `tempo-config.yml` |

### 5.4 OpenTelemetry Collector Config

```yaml
# otel-collector/otel-collector-config.yml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
  journald:
    directory: /run/log/journal
    units:
      - nginx
      - app.service

processors:
  batch:
    timeout: 5s
  resource:
    attributes:
      - key: deployment.environment
        value: production
        action: upsert

exporters:
  loki:
    endpoint: http://localhost:3100/loki/api/v1/push
    labels:
      resource:
        service.name: service_name
        deployment.environment: env
  otlp/tempo:
    endpoint: localhost:4317
    tls:
      insecure: true

service:
  pipelines:
    logs:
      receivers: [otlp, journald]
      processors: [batch, resource]
      exporters: [loki]
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/tempo]
```

### 5.5 Restart Policies

All services use `Restart=on-failure` with `RestartSec=5s` in their systemd unit files. Services are enabled with `systemctl enable` so they start automatically after a reboot. To confirm:

```bash
systemctl is-enabled prometheus loki tempo grafana-server alertmanager \
  node-exporter blackbox-exporter otel-collector
# All should output: enabled
```

---

## 6. Part 2 — Four Golden Signals as SLIs

The Four Golden Signals (Google SRE Book) describe a service's health comprehensively. Each becomes a measurable SLI expressed as a PromQL ratio or rate.

### Signal 1 — Latency

**Definition:** Time to serve a request. Successful and failed requests tracked separately.

```promql
# P99 latency of successful requests (SLI)
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{status!~"5.."}[5m])) by (le, service)
)

# P95 latency (SLO target threshold)
histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket{status!~"5.."}[5m])) by (le, service)
)

# Ratio of requests completing under 500ms (for SLO compliance)
sum(rate(http_request_duration_seconds_bucket{le="0.5", status!~"5.."}[30d]))
/
sum(rate(http_request_duration_seconds_count{status!~"5.."}[30d]))
```

### Signal 2 — Traffic

**Definition:** Demand placed on the system — requests per second.

```promql
# Current RPS across all services
sum(rate(http_requests_total[5m])) by (service, method)

# GitHub Actions pipeline trigger rate (CI/CD traffic)
sum(rate(github_actions_workflow_run_total[1h])) by (workflow, status)
```

### Signal 3 — Errors

**Definition:** Rate of failed requests — explicit 5xx, implicit wrong content, and policy timeouts.

```promql
# Error ratio (SLI — used for SLO compliance)
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))

# Blackbox probe failure ratio
1 - avg(avg_over_time(probe_success[5m]))
```

### Signal 4 — Saturation

**Definition:** How full the service is — the signal that predicts future failure.

```promql
# CPU saturation
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory saturation
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
/ node_memory_MemTotal_bytes * 100

# Disk saturation
(node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_free_bytes{mountpoint="/"})
/ node_filesystem_size_bytes{mountpoint="/"} * 100
```

---

## 7. Part 3 — SLOs & Error Budgets

### 7.1 SLO Definitions

All SLOs use a **rolling 30-day window**.

| SLO | Target | SLI Expression | Rationale |
|---|---|---|---|
| **Availability** | 99.5% | `avg_over_time(probe_success[30d])` | 2xx HTTP probes — industry standard for non-critical web services |
| **Latency** | 95% of requests < 500ms | Latency ratio (see Part 2) | 500ms is the UX threshold below which users perceive responses as instant |
| **Error Rate** | 99% success (non-5xx) | `1 - error_ratio` | 1% error rate allows buffer for transient failures and edge cases |
| **Saturation** | CPU < 80% p95 | CPU saturation PromQL | Leaves 20% headroom for traffic spikes before degradation |

### 7.2 Error Budget Calculations

**Formula:** `Error Budget = (1 - SLO_target) × measurement_window_in_minutes`

| SLO | Target | Budget (30 days = 43,200 min) |
|---|---|---|
| Availability 99.5% | 0.5% error allowed | 216 minutes of downtime |
| Latency 95% | 5% slow allowed | 2,160 minutes of slow requests |
| Error Rate 99% | 1% errors allowed | 432 minutes of error-rate violations |

### 7.3 Burn Rate Explained

Burn rate measures how fast you are consuming your error budget relative to ideal consumption rate.

- **Burn rate = 1.0** → consuming budget exactly in line with the 30-day window (sustainable).
- **Burn rate = 14.4** → consuming budget 14.4x faster. At this rate 2% of the monthly budget is gone in 1 hour (Fast Burn trigger).
- **Burn rate = 5.0** → consuming 5x faster. 5% of budget gone in 6 hours (Slow Burn trigger).

```promql
# Burn rate PromQL (1-hour window)
(
  sum(rate(http_requests_total{status=~"5.."}[1h]))
  /
  sum(rate(http_requests_total[1h]))
) / (1 - 0.99)
```

### 7.4 Grafana Error Budget Panels

All panels provisioned via `grafana/dashboards/slo-error-budget.json`:

- **Gauge — Budget Remaining (%):** Green >50%, yellow 10–50%, red <10%.
- **Gauge — Budget Remaining (absolute minutes):** Shows absolute time left.
- **Time Series — Burn Rate:** Two horizontal reference lines at 14.4x and 5x.
- **Stat — SLO Compliance 7-day / 30-day:** Pass/Fail indicator with colour coding.

---

## 8. Part 4 — DORA Metrics & CI/CD Observability

### 8.1 The Four DORA Metrics

#### Deployment Frequency (DF)

Measures how often you deploy to production.

| Classification | Frequency |
|---|---|
| Elite | Multiple times per day |
| High | Between once per day and once per week |
| Medium | Between once per week and once per month |
| Low | Less than once per month |

```promql
# Deployments in the last 7 days
increase(github_actions_deployments_total{environment="production"}[7d])

# Daily deployment rate
rate(github_actions_deployments_total{environment="production"}[24h]) * 86400
```

#### Lead Time for Changes (LTC)

Time from code commit to production deployment, broken into:

| Sub-interval | Measurement |
|---|---|
| Commit → Pipeline Trigger | `workflow_queued_at - commit_timestamp` |
| Pipeline Trigger → Complete | `workflow_completed_at - workflow_queued_at` |
| Pipeline Complete → Deploy Confirmed | `deploy_confirmed_at - workflow_completed_at` |
| **Total LTC** | `deploy_confirmed_at - commit_timestamp` |

```promql
# Median LTC in seconds
histogram_quantile(0.50, 
  sum(rate(github_actions_lead_time_seconds_bucket[7d])) by (le)
)
```

#### Change Failure Rate (CFR)

```promql
# Raw CFR — deployments resulting in failure/rollback/hotfix
sum(github_actions_deployments_total{result=~"failure|rollback|hotfix"})
/
sum(github_actions_deployments_total)

# Rolling 7-day CFR
sum(increase(github_actions_deployments_total{result=~"failure|rollback|hotfix"}[7d]))
/
sum(increase(github_actions_deployments_total[7d]))
```

**DORA CFR Benchmarks:**

| Classification | CFR |
|---|---|
| Elite | 0–5% |
| High | 5–10% |
| Medium | 10–15% |
| Low | 15–100% |

#### Mean Time to Restore (MTTR)

```promql
# MTTR — average time from alert firing to resolution (seconds)
avg(github_actions_incident_duration_seconds)

# P90 MTTR
histogram_quantile(0.90,
  sum(rate(github_actions_incident_duration_seconds_bucket[30d])) by (le)
)
```

### 8.2 GitHub Actions Integration

Deployment events are pushed to Prometheus Pushgateway from within the GitHub Actions workflow:

```yaml
# In your GitHub Actions workflow
- name: Push deployment metrics
  run: |
    cat <<EOF | curl --data-binary @- http://${{ secrets.PUSHGATEWAY_URL }}/metrics/job/github_actions
    # HELP github_actions_deployments_total Total deployments
    # TYPE github_actions_deployments_total counter
    github_actions_deployments_total{environment="production",result="success",workflow="deploy"} 1
    EOF
```

---

## 9. Part 5 — Grafana Dashboards

All dashboards are provisioned as JSON files in `grafana/dashboards/`. The dashboard provider in `grafana/provisioning/dashboards/dashboards.yml` loads them automatically.

**Never configure dashboards in the Grafana UI.** All changes go into the JSON files and are deployed via IaC.

### 9.1 Datasource Provisioning

```yaml
# grafana/provisioning/datasources/datasources.yml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://localhost:9090
    isDefault: true
    jsonData:
      timeInterval: "15s"

  - name: Loki
    type: loki
    url: http://localhost:3100
    jsonData:
      derivedFields:
        - name: TraceID
          matcherRegex: "traceID=(\\w+)"
          url: "${__value.raw}"
          datasourceUid: tempo
          urlDisplayLabel: "Open in Tempo"

  - name: Tempo
    type: tempo
    url: http://localhost:3200
    jsonData:
      tracesToLogs:
        datasourceUid: loki
        tags: ['service.name', 'instance']
        mappedTags:
          - key: service.name
            value: service_name
        lokiSearch: true
      serviceMap:
        datasourceUid: prometheus
```

### 9.2 Dashboard Index

| Dashboard | File | Key Panels |
|---|---|---|
| DORA Metrics | `dora-metrics.json` | DF gauge + classification, LTC histogram, CFR gauge, MTTR stat |
| SLO & Error Budget | `slo-error-budget.json` | SLI vs SLO gauges, budget remaining bar gauge, burn rate time series |
| Node Exporter | `node-exporter.json` | CPU (total + per-core), memory breakdown, disk I/O, network I/O, load avg |
| Blackbox Exporter | `blackbox-exporter.json` | Uptime timeline, HTTP response time p50/p90/p99, SSL expiry, probe success |
| Unified Observability | `unified-observability.json` | Error rate + latency panels with Loki/Tempo drill-down links |

### 9.3 Unified Observability Dashboard — Drill-Down Flow

This is the most critical dashboard. The acceptance criterion is:

1. Engineer sees a **spike in error rate** or **latency panel**.
2. Clicks the panel → navigates to **Loki Explore** filtered to the same time window.
3. In Loki, sees log lines with `traceID=` fields rendered as clickable links (derived fields).
4. Clicks trace ID → opens **Tempo trace view** showing the exact span tree.
5. Identifies the slow/failing **service, endpoint, and root cause** from the span data.

This correlation is achieved via:
- **Loki derived fields** (configured in datasource provisioning above).
- **Grafana panel links** with `${__from}` and `${__to}` time variables.
- Applications embedding trace IDs in structured log output.

---

## 10. Part 6 — Alerting System

### 10.1 Infrastructure Alert Rules

```yaml
# prometheus/rules/infrastructure.yml
groups:
  - name: infrastructure
    rules:
      - alert: CPUWarning
        expr: |
          (100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is {{ $value | humanize }}% (threshold: 80%)"
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/cpu-warning.md"

      - alert: CPUCritical
        expr: |
          (100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) > 90
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Critical CPU usage on {{ $labels.instance }}"
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/cpu-critical.md"

      - alert: MemoryWarning
        expr: |
          (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
          / node_memory_MemTotal_bytes * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/memory-warning.md"

      - alert: MemoryCritical
        expr: |
          (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
          / node_memory_MemTotal_bytes * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/memory-critical.md"

      - alert: DiskWarning
        expr: |
          (node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_free_bytes{mountpoint="/"})
          / node_filesystem_size_bytes{mountpoint="/"} * 100 > 75
        for: 5m
        labels:
          severity: warning
        annotations:
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/disk-warning.md"

      - alert: DiskCritical
        expr: |
          (node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_free_bytes{mountpoint="/"})
          / node_filesystem_size_bytes{mountpoint="/"} * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/disk-critical.md"

      - alert: HostDown
        expr: probe_success{job="blackbox-http"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Host {{ $labels.instance }} is unreachable"
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/host-down.md"
```

### 10.2 SLO Burn Rate Alert Rules

```yaml
# prometheus/rules/slo-burn-rate.yml
groups:
  - name: slo-burn-rate
    rules:
      # Fast Burn — 2% budget consumed in 1 hour (14.4x burn rate)
      - alert: SLOFastBurn
        expr: |
          (
            sum(rate(http_requests_total{status=~"5.."}[1h]))
            / sum(rate(http_requests_total[1h]))
          ) / (1 - 0.99) > 14.4
          and
          (
            sum(rate(http_requests_total{status=~"5.."}[5m]))
            / sum(rate(http_requests_total[5m]))
          ) / (1 - 0.99) > 14.4
        for: 2m
        labels:
          severity: critical
          slo: error_rate
        annotations:
          summary: "CRITICAL: SLO fast burn — error budget being consumed at {{ $value | humanizePercentage }} rate"
          description: "2% of the monthly error budget will be consumed in 1 hour at this rate."
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/slo-fast-burn.md"
          dashboard_url: "http://localhost:3000/d/slo-error-budget"

      # Slow Burn — 5% budget consumed in 6 hours (5x burn rate)
      - alert: SLOSlowBurn
        expr: |
          (
            sum(rate(http_requests_total{status=~"5.."}[6h]))
            / sum(rate(http_requests_total[6h]))
          ) / (1 - 0.99) > 5
          and
          (
            sum(rate(http_requests_total{status=~"5.."}[30m]))
            / sum(rate(http_requests_total[30m]))
          ) / (1 - 0.99) > 5
        for: 15m
        labels:
          severity: warning
          slo: error_rate
        annotations:
          summary: "WARNING: SLO slow burn — 5% of error budget at risk over next 6 hours"
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/slo-slow-burn.md"
```

### 10.3 CI/CD Alert Rules

```yaml
# prometheus/rules/cicd.yml
groups:
  - name: cicd
    rules:
      - alert: CFRThresholdExceeded
        expr: |
          sum(increase(github_actions_deployments_total{result=~"failure|rollback|hotfix"}[7d]))
          / sum(increase(github_actions_deployments_total[7d])) > 0.10
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Change Failure Rate exceeds 10% SLO threshold"
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/cfr-threshold-exceeded.md"

      - alert: MTTRExceeded
        expr: |
          avg(github_actions_incident_duration_seconds) > 3600
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MTTR exceeds 1-hour maximum SLO"
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/mttr-exceeded.md"
```

### 10.4 Alertmanager Configuration

```yaml
# alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m
  slack_api_url: '<YOUR_SLACK_WEBHOOK_URL>'

templates:
  - '/etc/alertmanager/templates/*.tmpl'

route:
  group_by: ['service', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'slack-devops-alerts'
  routes:
    - match:
        severity: critical
      receiver: 'slack-devops-alerts'
      repeat_interval: 1h
    - match:
        severity: warning
      receiver: 'slack-devops-alerts'
      repeat_interval: 4h

inhibit_rules:
  # Suppress CPU/memory/latency noise when host is fully unreachable
  - source_match:
      alertname: 'HostDown'
    target_match_re:
      alertname: 'CPU.*|Memory.*|Disk.*|SLO.*'
    equal: ['instance']

receivers:
  - name: 'slack-devops-alerts'
    slack_configs:
      - channel: '#DevOps-Alerts'
        send_resolved: true
        title: '{{ template "slack.title" . }}'
        text: '{{ template "slack.text" . }}'
        color: '{{ template "slack.color" . }}'
```

### 10.5 Structured Slack Template

```
# alertmanager/templates/slack.tmpl
{{ define "slack.title" -}}
{{ if eq .Status "firing" }}🔴{{ else }}✅{{ end }} [{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}
{{- end }}

{{ define "slack.color" -}}
{{ if eq .Status "resolved" }}good
{{ else if eq .CommonLabels.severity "critical" }}danger
{{ else }}warning
{{ end }}
{{- end }}

{{ define "slack.text" -}}
{{ range .Alerts }}
*Alert:* {{ .Labels.alertname }}
*Severity:* {{ .Labels.severity }}
*Host:* {{ .Labels.instance | default "N/A" }}
*Status:* {{ .Status }}
*Value:* {{ .Annotations.description | default "See dashboard" }}
*Started:* {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}
{{ if eq .Status "resolved" }}*Resolved:* {{ .EndsAt.Format "2006-01-02 15:04:05 UTC" }}{{ end }}

*Links:*
• <{{ .Annotations.dashboard_url | default "http://localhost:3000" }}|Grafana Dashboard>
• <{{ .Annotations.runbook_url }}|Runbook>
{{ end }}
{{- end }}
```

---

## 11. Part 7 — Incident Management & Runbooks

### 11.1 Runbook Template

Every runbook in `runbooks/` follows this structure:

```markdown
# Runbook: [Alert Name]

## What Is This Alert?
Plain-English description of what the alert means.

## Likely Causes
Ranked list of probable root causes.

## Investigation Steps
1. Check [...] — `<command or Grafana panel link>`
2. Inspect [...] — `<LogQL/PromQL query>`
3. Verify [...] — `<specific action>`

## Resolution
Step-by-step fix instructions.

## Should I Roll Back?
Decision tree: when to roll back vs. patch forward.

## Escalation
When to escalate and to whom.
```

### 11.2 Post-Incident Review Structure

Located in `incidents/pir-001-latency-spike.md`:

| Section | Contents |
|---|---|
| Incident Summary | Severity, duration, impact |
| Timeline | Detection → Response → Resolution (minute-by-minute) |
| Root Cause | What actually failed and why |
| Detection Gap | What the monitoring missed or was slow on |
| Action Items | Owner + due date for every follow-up |
| Lessons Learned | What the team will do differently |

---

## 12. Part 8 — Game Day: Chaos & Failure Simulation

### Scenario 1 — Deployment Failure

**Objective:** Confirm CFR alert fires and DORA dashboard updates.

**Steps:**
1. Introduce a deliberate syntax error into the app's Dockerfile.
2. Push to main → trigger GitHub Actions.
3. Observe the pipeline fail → Pushgateway receives `result="failure"` metric.
4. Confirm `CFRThresholdExceeded` alert fires in `#DevOps-Alerts` within 10 minutes.
5. Screenshot: DORA dashboard showing CFR spike.
6. Fix the error → push again → confirm recovery alert in Slack.

**Expected Timeline:**

```
T+0:00  — Bad commit pushed
T+0:02  — GitHub Actions workflow triggered
T+0:08  — Workflow fails, pushes failure metric to Pushgateway
T+0:10  — Prometheus evaluates CFR rule → alert enters PENDING
T+0:20  — Alert fires → Alertmanager routes to Slack
T+0:21  — Slack notification received in #DevOps-Alerts
```

### Scenario 2 — Latency Injection

**Objective:** Observe SLI degrade → burn rate increase → Fast Burn alert fire → correlated trace in Tempo.

**Steps:**
1. Inject artificial latency using `tc netem` or application-level sleep.
2. Watch latency SLI panel in Grafana cross the 500ms threshold.
3. Observe burn rate time series climb above 14.4x.
4. Confirm `SLOFastBurn` alert fires.
5. Click through Loki derived field (trace ID) → open in Tempo.
6. Identify the slow span in the trace waterfall.

### Scenario 3 — Resource Pressure

**Objective:** Confirm warning fires before critical, and recovery alerts send when pressure clears.

**Steps:**
1. Run `stress --cpu 8 --timeout 300s` on the host.
2. Confirm `CPUWarning` fires at >80% after 5 minutes.
3. Continue stress → confirm `CPUCritical` fires at >90% after 10 minutes.
4. Kill stress process → confirm both alerts resolve in Slack with `✅ [RESOLVED]`.

---

## 13. Error Budget Policy

**Document Location:** `slo/error-budget-policy.md`

| Budget Consumed | Action | Owner |
|---|---|---|
| 0–25% | Normal operations. Feature development proceeds. | Engineering |
| 25–50% | Reliability review in next sprint planning. | Engineering Lead |
| 50–75% | Reduce feature work by 20%. One reliability improvement required per sprint. | Engineering Lead + PM |
| 75–100% | Feature freeze. All engineering effort on reliability sprint. | Engineering Lead + PM |
| **100% (depleted)** | Full reliability sprint. No feature deployments until SLO is met for 7 consecutive days. | CTO decision |

**SLO Review Cadence:** Monthly review with Engineering Lead and PM.  
**SLO Change Process:** Proposed changes require evidence (30 days of SLI data) and sign-off from Engineering Lead.

---

## 14. Toil Identification & Automation

### Identified Toil

| # | Toil Description | Time Cost | Automation Strategy | Status |
|---|---|---|---|---|
| 1 | Manually creating Grafana dashboards via UI after each re-deploy | ~2 hours per environment setup | Grafana provisioning via JSON + IaC (Terraform) | **Implemented** |
| 2 | Manually pushing deployment metrics to Pushgateway | ~5 min per deployment | GitHub Actions step in CI/CD workflow | **Implemented** |
| 3 | Manually acknowledging and silencing known-good maintenance alerts | ~15 min per maintenance window | Alertmanager scheduled silences via API call in maintenance script | Proposed |
| 4 | Manually generating PIR documents after incidents | ~1 hour per incident | PIR template + automated timeline generation from alert history | Proposed |

---

## 15. Technology Choices & Philosophy

### SLIs, SLOs, and Error Budgets — Why They Matter

Traditional monitoring asks "is it up?" SRE asks "is it reliable enough to meet user expectations?" The SLI/SLO/Error Budget framework:

- **SLI** (Service Level Indicator): A quantitative measure of service behaviour from the user's perspective.
- **SLO** (Service Level Objective): The target value for an SLI that defines what "good enough" means.
- **Error Budget**: The inverse of the SLO — the allowable margin for failure. This is the key innovation: it turns reliability into a product conversation, not just an ops concern.

### Four Golden Signals — Beyond CPU/RAM

CPU and RAM are internal system metrics. They measure machine health, not user experience. The Four Golden Signals (Latency, Traffic, Errors, Saturation) map directly to what users experience:

- A slow page (high latency) upsets users even when CPU is low.
- A high error rate means users are failing their tasks.
- Saturation predicts future failures before they happen.

### DORA Metrics — Engineering to Business Outcomes

DORA metrics connect team habits to measurable business outcomes:

- **High DF + Low CFR** = team can ship frequently without breaking things → competitive advantage.
- **Low LTC** = faster response to market feedback.
- **Low MTTR** = failures are recovered quickly → less customer impact → less revenue loss.

### Burn Rate Alerting — Reducing Alert Fatigue

Threshold-based alerting (alert when error rate > 1%) leads to alert fatigue because small spikes fire alerts even if they will not breach the SLO. Burn rate alerting asks: "at this rate, will we breach our monthly SLO?" This means:

- Fewer alerts overall (only fire when the budget is genuinely at risk).
- Higher signal-to-noise ratio.
- Alerts are always actionable — you know exactly how much time you have to respond.

---

*Last updated: May 2026 | Team: Pabby & Trojan*

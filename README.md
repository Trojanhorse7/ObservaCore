# ObservaCore — Production-Grade Observability Platform

> LGTP Stack · SLOs · DORA Metrics · Burn Rate Alerting · Incident Management

Built by **Pabby** and **Trojan** as part of the DevOps Track — Stage 6.

---

## What This Is

ObservaCore is a self-hosted observability platform built on the **LGTP stack** (Loki, Grafana, Tempo, Prometheus). It goes beyond simple up/down monitoring into user-centric reliability engineering using SLIs, SLOs, error budgets, and burn rate alerting.

The platform gives any engineering team:

- A unified view of metrics, logs, and traces in a single Grafana instance
- SLO compliance tracking with error budget remaining and burn rate
- DORA metrics (Deployment Frequency, Lead Time, CFR, MTTR) pulled from GitHub Actions
- Structured Slack alerts routed to `#DevOps-Alerts` with runbook links
- Full log-to-trace drill-down: metric spike → Loki logs → Tempo trace → root cause

---

## Stack

| Component | Version | Port | Purpose |
|---|---|---|---|
| Prometheus | 2.51+ | 9090 | Metrics scrape and storage |
| Loki | 3.0+ | 3100 | Log aggregation |
| Tempo | 2.4+ | 3200 | Distributed tracing |
| Grafana | 10.4+ | 3000 | Unified observability UI |
| Alertmanager | 0.27+ | 9093 | Alert routing and deduplication |
| Node Exporter | 1.7+ | 9100 | System metrics (CPU, RAM, disk, network) |
| Blackbox Exporter | 0.24+ | 9115 | HTTP probe and SSL expiry monitoring |
| OTel Collector | 0.97+ | 4317/4318 | Telemetry pipeline (logs → Loki, traces → Tempo) |

All services run as native Linux binaries managed by **systemd**. No Docker.

---

## One-Command Deployment

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set your server IP, Slack webhook URL, target URLs
terraform init && terraform apply -auto-approve
```

Terraform will:
1. Create a dedicated system user for each service
2. Download the correct binary version
3. Write all config files from templates
4. Install and enable systemd unit files
5. Start every service and set it to start on boot

### Verify the stack is healthy

```bash
systemctl is-active prometheus loki tempo grafana-server alertmanager \
  node-exporter blackbox-exporter otel-collector

curl http://localhost:9090/-/healthy   # Prometheus Server is Healthy.
curl http://localhost:3100/ready       # ready
curl http://localhost:3200/ready       # ready
```

---

## Repository Structure

```
ObservaCore/
├── .github/
│   ├── workflows/deploy.yml          # CI/CD pipeline + DORA metric push
│   └── PULL_REQUEST_TEMPLATE.md
├── alertmanager/
│   ├── alertmanager.yml              # Route tree + inhibition rules
│   └── templates/slack.tmpl         # Structured Slack notification template
├── game-day/
│   ├── scenario-1-deployment-failure.md
│   ├── scenario-2-latency-injection.md
│   └── scenario-3-resource-pressure.md
├── grafana/
│   ├── dashboards/
│   │   ├── dora-metrics.json
│   │   ├── slo-error-budget.json
│   │   └── unified-observability.json
│   └── provisioning/
│       ├── dashboards/dashboards.yml
│       └── datasources/datasources.yml
├── loki/
│   └── loki-config.yml
├── otel-collector/
│   └── otel-collector-config.yml
├── prometheus/
│   ├── prometheus.yml
│   └── rules/
│       ├── infrastructure.yml        # CPU, memory, disk, host down, SSL
│       ├── slo-burn-rate.yml         # Multi-window fast/slow burn rate rules
│       └── cicd.yml                  # CFR, MTTR, pipeline activity rules
├── runbooks/
│   ├── cpu-high.md
│   ├── memory-high.md
│   ├── disk-high.md
│   ├── server-down.md
│   ├── slo-fast-burn.md
│   └── high-cfr.md
├── slo/
│   └── slo-definitions.md
├── tempo/
│   └── tempo-config.yml
```

---

## Dashboards

All dashboards are provisioned as JSON — never configured through the Grafana UI.

| Dashboard | File | Description |
|---|---|---|
| DORA Metrics | `dora-metrics.json` | DF, LTC, CFR, MTTR with Elite/High/Medium/Low classification |
| SLO & Error Budget | `slo-error-budget.json` | SLI gauges, budget remaining, burn rate time series |
| Node Exporter | *(Pabby)* | CPU, memory, disk I/O, network I/O, load averages |
| Blackbox Exporter | *(Pabby)* | Uptime, HTTP response times, SSL expiry countdown |
| Unified Observability | `unified-observability.json` | Metric → Loki log → Tempo trace drill-down |

---

## Alert Rules

All rules are in `prometheus/rules/` as version-controlled `.yml` files.

### Infrastructure Alerts

| Alert | Condition | For | Severity |
|---|---|---|---|
| CPUWarning | CPU > 80% | 5m | warning |
| CPUCritical | CPU > 90% | 10m | critical |
| MemoryWarning | RAM > 80% | 5m | warning |
| MemoryCritical | RAM > 90% | 5m | critical |
| DiskWarning | Disk > 75% | 5m | warning |
| DiskCritical | Disk > 90% | 5m | critical |
| HostDown | Probe fails | 2m | critical |
| SSLCertExpiryWarning | Cert expires < 30 days | 1h | warning |
| SSLCertExpiryCritical | Cert expires < 7 days | 1h | critical |

### SLO Burn Rate Alerts (Multi-Window)

| Alert | Burn Rate | Windows | Severity |
|---|---|---|---|
| SLOFastBurn | > 14.4x | 1h + 5m | critical |
| SLOSlowBurn | > 5x | 6h + 30m | warning |
| AvailabilityFastBurn | > 14.4x | 1h | critical |
| AvailabilitySlowBurn | > 5x | 6h | warning |
| LatencyFastBurn | > 14.4x | 1h | critical |
| LatencySlowBurn | > 5x | 6h | warning |

### CI/CD Alerts

| Alert | Condition | Severity |
|---|---|---|
| CFRThresholdExceeded | CFR > 10% over 7 days | critical |
| CFRThresholdWarning | CFR > 5% over 7 days | warning |
| MTTRExceeded | Avg MTTR > 60 minutes | warning |
| NoPipelineActivity | No deployments in 7 days | warning |

---

## SLOs

Defined in `slo/slo-definitions.md`. All use a rolling 30-day window.

| SLO | Target | Error Budget |
|---|---|---|
| Availability | 99.5% | 216 min/month |
| Latency (< 500ms) | 95% of requests | 5% of requests |
| Error Rate | 99% success | 432 min/month |
| CPU Saturation | < 80% p95 | — |

### Error Budget Policy

| Budget Consumed | Action |
|---|---|
| 0–25% | Normal operations |
| 25–50% | Reliability review in next sprint |
| 50–75% | Feature velocity reduced 20% |
| 75–100% | Feature freeze |
| 100% | Full reliability sprint. No deploys until SLO met for 7 days |

---

## DORA Metrics

GitHub Actions pushes deployment metrics to Prometheus Pushgateway on every pipeline run.

| Metric | Elite | High | Medium | Low |
|---|---|---|---|---|
| Deployment Frequency | Multiple/day | Daily | Weekly | Monthly |
| Lead Time | < 1 hour | < 1 day | < 1 week | > 1 week |
| Change Failure Rate | 0–5% | 5–10% | 10–15% | > 15% |
| MTTR | < 1 hour | < 1 day | < 1 week | > 1 week |

Required GitHub Actions secrets: `PUSHGATEWAY_URL`, `GRAFANA_URL`

---

## Alerting

All alerts route to `#DevOps-Alerts` in Slack with structured payloads including alert name, severity, host, metric value, Grafana dashboard link, and runbook link.

### Inhibition Rules

- `HostDown` suppresses all CPU, memory, disk, and SLO alerts for the same instance
- `CPUCritical` suppresses `CPUWarning` for the same instance
- `MemoryCritical` suppresses `MemoryWarning` for the same instance
- `SLOFastBurn` suppresses `SLOSlowBurn` for the same SLO

### Required Secret

Set `slack_api_url` in `alertmanager/alertmanager.yml` to your Slack incoming webhook URL.

---

## Runbooks

Every alert rule has a corresponding runbook in `runbooks/`. Each covers: what the alert means, likely causes, 3 investigation steps, resolution, rollback decision, and escalation path.

---

## Game Day

Three chaos scenarios documented in `game-day/`:

1. **Deployment Failure** — trigger a failing pipeline, confirm CFR alert fires in Slack
2. **Latency Injection** — inject 600ms latency, follow the full metric → log → trace drill-down
3. **Resource Pressure** — CPU stress, confirm warning fires before critical, confirm recovery

---

## Team

| Engineer | Owns |
|---|---|
| **Pabby** | LGTP stack deployment (Terraform + systemd), Loki/Tempo/OTel configs, Four Golden Signals SLIs, SLO definitions, error budget policy, Node Exporter dashboard, Blackbox Exporter dashboard, all runbooks, Post-Incident Review |
| **Trojan** | Alert rules, Alertmanager routing + Slack templates, DORA metrics + GitHub Actions integration, DORA dashboard, SLO/Error Budget dashboard, Unified Observability dashboard, Game Day execution |

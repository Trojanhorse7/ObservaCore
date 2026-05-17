# Pabby's Task Breakdown
## Observability Platform — DevOps Stage 6

> **Engineer:** Pabby  
> **Partner:** Trojan  
> **Full project reference:** [main-doc.md](./main-doc.md)

---

## Overview of Your Responsibilities

You own the **infrastructure foundation and reliability definition** of this platform. While Trojan builds the dashboards, alerting system, and DORA pipeline, you are responsible for everything that sits underneath — the stack itself, what reliability *means* for the service, and what happens when things go wrong.

Your work is split across four areas:

| Area | Parts Covered | Deliverables |
|---|---|---|
| Deploy & harden the LGTM stack | Part 1 | Docker Compose / Terraform IaC, all config files |
| Define the Four Golden Signals | Part 2 | SLI PromQL expressions, signal definitions |
| Define SLOs & Error Budgets | Part 3 | SLO targets, error budget calculations, budget policy |
| Incident Management & Runbooks | Part 7 | Runbooks for every alert, one blameless PIR |

---

## Table of Contents

1. [Your Files & Ownership Map](#1-your-files--ownership-map)
2. [Part 1 — Deploy & Harden the LGTM Stack](#2-part-1--deploy--harden-the-lgtm-stack)
3. [Part 2 — Four Golden Signals as SLIs](#3-part-2--four-golden-signals-as-slis)
4. [Part 3 — SLOs & Error Budgets](#4-part-3--slos--error-budgets)
5. [Part 7 — Incident Management & Runbooks](#5-part-7--incident-management--runbooks)
6. [Grafana Dashboards You Own](#6-grafana-dashboards-you-own)
7. [Presentation Slides — Your Sections](#7-presentation-slides--your-sections)
8. [Blog Post — Your Sections](#8-blog-post--your-sections)
9. [Checklist](#9-checklist)

---

## 1. Your Files & Ownership Map

You are the primary author of the following files. Create them, keep them updated, and make sure they are committed to the repository.

```
observability-platform/
│
├── terraform/                          ← YOU own the full directory
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── prometheus/
│       ├── loki/
│       ├── tempo/
│       ├── grafana/
│       ├── alertmanager/
│       ├── node-exporter/
│       ├── blackbox-exporter/
│       └── otel-collector/
│
├── systemd/                            ← YOU own this directory
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
│   ├── install.sh                      ← YOU own this
│   └── verify.sh                       ← YOU own this
│
├── prometheus/
│   └── prometheus.yml                  ← YOU own this (scrape configs)
│
├── loki/
│   └── loki-config.yml                 ← YOU own this
│
├── tempo/
│   └── tempo-config.yml                ← YOU own this
│
├── otel-collector/
│   └── otel-collector-config.yml       ← YOU own this
│
├── slo/
│   ├── slo-definitions.yml             ← YOU own this
│   └── error-budget-policy.md          ← YOU own this
│
├── runbooks/                           ← YOU own ALL files here
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
├── incidents/
│   └── pir-001-latency-spike.md        ← YOU own this
│
├── grafana/dashboards/
│   ├── node-exporter.json              ← YOU own this
│   └── blackbox-exporter.json          ← YOU own this
│
└── README.md                           ← SHARED (you write the stack & SLO sections)
```

---

## 2. Part 1 — Deploy & Harden the LGTM Stack

### Your Goal

Provision the entire observability stack using **Terraform with systemd services**. No Docker or containers of any kind. Every service is a native Linux binary running under its own system user, managed by systemd, and configured through files in `/etc/`.

One command brings everything up: `terraform init && terraform apply -auto-approve`

### Step-by-Step

#### Step 1 — Write `scripts/install.sh`

This script is the bootstrap called by Terraform before any modules run. It sets up the base system.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Create system users (no login shell, no home directory)
for svc in prometheus loki tempo grafana alertmanager node_exporter blackbox_exporter otelcol; do
  id "$svc" &>/dev/null || useradd --no-create-home --shell /bin/false "$svc"
done

# Create config and data directories
declare -A dirs=(
  [prometheus]="/etc/prometheus /var/lib/prometheus"
  [loki]="/etc/loki /var/lib/loki"
  [tempo]="/etc/tempo /var/lib/tempo"
  [grafana]="/etc/grafana /var/lib/grafana /var/lib/grafana/dashboards"
  [alertmanager]="/etc/alertmanager /var/lib/alertmanager"
  [otelcol]="/etc/otelcol"
)

for user in "${!dirs[@]}"; do
  for dir in ${dirs[$user]}; do
    mkdir -p "$dir"
    chown "$user":"$user" "$dir"
  done
done
```

#### Step 2 — Write systemd Unit Files (`systemd/`)

Create one `.service` file per component. All follow the same pattern — see `main-doc.md` Section 5.1a. Key flags per service:

**prometheus.service:**
```
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=30d \
  --web.enable-lifecycle
```

**loki.service:**
```
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yml
```

**tempo.service:**
```
ExecStart=/usr/local/bin/tempo -config.file=/etc/tempo/tempo-config.yml
```

**grafana-server.service:**
```
ExecStart=/usr/sbin/grafana-server \
  --config=/etc/grafana/grafana.ini \
  --homepath=/usr/share/grafana
```

**alertmanager.service:**
```
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager
```

**node-exporter.service:**
```
ExecStart=/usr/local/bin/node_exporter \
  --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|run)($|/)'
```

**blackbox-exporter.service:**
```
ExecStart=/usr/local/bin/blackbox_exporter \
  --config.file=/etc/blackbox-exporter/blackbox.yml
```

**otel-collector.service:**
```
ExecStart=/usr/local/bin/otelcol-contrib --config=/etc/otelcol/otel-collector-config.yml
```

#### Step 3 — Write Terraform Root `main.tf`

```hcl
# terraform/main.tf
terraform {
  required_providers {
    null   = { source = "hashicorp/null" }
    local  = { source = "hashicorp/local" }
  }
}

# Bootstrap: users and directories
resource "null_resource" "bootstrap" {
  provisioner "local-exec" {
    command = "bash ${path.root}/../scripts/install.sh"
  }
}

module "prometheus"      { source = "./modules/prometheus";      depends_on = [null_resource.bootstrap] }
module "loki"            { source = "./modules/loki";            depends_on = [null_resource.bootstrap] }
module "tempo"           { source = "./modules/tempo";           depends_on = [null_resource.bootstrap] }
module "grafana"         { source = "./modules/grafana";         depends_on = [null_resource.bootstrap] }
module "alertmanager"    { source = "./modules/alertmanager";    depends_on = [null_resource.bootstrap] }
module "node_exporter"   { source = "./modules/node-exporter";   depends_on = [null_resource.bootstrap] }
module "blackbox"        { source = "./modules/blackbox-exporter"; depends_on = [null_resource.bootstrap] }
module "otel_collector"  { source = "./modules/otel-collector";  depends_on = [null_resource.bootstrap] }
```

Each module follows the pattern in `main-doc.md` Section 5.1b:
1. `null_resource` downloads the binary with `wget` and places it in `/usr/local/bin/`.
2. `local_file` writes the config from a Terraform template (`.tpl` file).
3. Second `null_resource` copies the systemd unit, runs `systemctl daemon-reload`, `enable`, and `restart`.

#### Step 5 — Write `prometheus.yml`

Copy the scrape config from `main-doc.md` Section 5.2. Since there is no Docker networking, use `localhost` for all targets:

- `scrape_interval: 15s` globally.
- Node Exporter target: `localhost:9100`.
- Blackbox Exporter target: `localhost:9115`.
- Rule files path: `/etc/prometheus/rules/*.yml`.
- Alertmanager target: `localhost:9093`.

#### Step 6 — Write Loki Config

```yaml
# loki/loki-config.yml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 1h
  max_chunk_age: 2h

schema_config:
  configs:
    - from: 2024-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/index_cache
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

compactor:
  working_directory: /loki/compactor
  shared_store: filesystem
  retention_enabled: true

limits_config:
  retention_period: 720h   # 30 days
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
```

#### Step 7 — Write Tempo Config

```yaml
# tempo/tempo-config.yml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

storage:
  trace:
    backend: local
    local:
      path: /var/tempo/blocks
    wal:
      path: /var/tempo/wal

compactor:
  compaction:
    block_retention: 168h   # 7 days
```

#### Step 8 — Write OpenTelemetry Collector Config

Use the config from `main-doc.md` Section 5.4. Since all services are on the same host, endpoints use `localhost`:

- Loki endpoint: `http://localhost:3100/loki/api/v1/push`
- Tempo endpoint: `localhost:4317`

#### Step 9 — OpenTelemetry Instrumentation

Instrument at least one service to emit traces. If your team does not have a custom application, instrument a simple Python or Node.js HTTP server:

```python
# Example: instrument a Flask app
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

provider = TracerProvider()
exporter = OTLPSpanExporter(endpoint="http://otel-collector:4317", insecure=True)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
```

Embed the trace ID in every log line:

```python
import logging
from opentelemetry import trace

def log_with_trace(message):
    span = trace.get_current_span()
    ctx = span.get_span_context()
    logging.info(f"traceID={format(ctx.trace_id, '032x')} {message}")
```

### Verification Checklist

After `terraform apply`, confirm:

- [ ] `systemctl is-active prometheus loki tempo grafana-server alertmanager node-exporter blackbox-exporter otel-collector` — all return `active`
- [ ] `systemctl is-enabled prometheus` (and all others) returns `enabled`
- [ ] `curl http://localhost:9090/-/healthy` returns `Prometheus Server is Healthy.`
- [ ] `curl http://localhost:3100/ready` returns `ready`
- [ ] `curl http://localhost:3200/ready` returns `ready`
- [ ] Grafana loads at `http://localhost:3000` (admin/admin)
- [ ] Alertmanager loads at `http://localhost:9093`
- [ ] Node Exporter metrics visible at `http://localhost:9100/metrics`
- [ ] Blackbox Exporter loads at `http://localhost:9115`
- [ ] All Prometheus targets show as `UP` at `http://localhost:9090/targets`
- [ ] `bash scripts/verify.sh` exits with code 0

---

## 3. Part 2 — Four Golden Signals as SLIs

### Your Goal

Before any dashboard is built, formally define what "reliable" means for your service. Write one PromQL expression per signal that produces a ratio or rate. These expressions are referenced by SLO definitions, alert rules, and Grafana panels.

### Deliverable: `slo/slo-definitions.yml`

```yaml
# slo/slo-definitions.yml
slos:
  - name: availability
    description: >
      Percentage of HTTP probes that return a successful 2xx response.
      Measured via Blackbox Exporter over a rolling 30-day window.
    sli_expression: |
      avg_over_time(probe_success{job="blackbox-http"}[30d])
    target: 0.995
    window: 30d
    golden_signal: errors

  - name: latency
    description: >
      Percentage of HTTP requests completing under 500ms.
      Excludes 5xx requests to avoid measuring error latency.
    sli_expression: |
      sum(rate(http_request_duration_seconds_bucket{le="0.5", status!~"5.."}[5m]))
      / sum(rate(http_request_duration_seconds_count{status!~"5.."}[5m]))
    target: 0.95
    window: 30d
    golden_signal: latency

  - name: error_rate
    description: >
      Percentage of requests succeeding (non-5xx).
      Covers explicit HTTP 5xx, implicit failures, and policy timeouts.
    sli_expression: |
      1 - (
        sum(rate(http_requests_total{status=~"5.."}[5m]))
        / sum(rate(http_requests_total[5m]))
      )
    target: 0.99
    window: 30d
    golden_signal: errors

  - name: saturation
    description: >
      CPU utilisation must remain below 80% at the p95 level.
      Saturation is an early warning — predicts future latency/errors.
    sli_expression: |
      quantile(0.95,
        100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
      )
    target: 80          # must stay BELOW this value
    window: 30d
    golden_signal: saturation
```

### PromQL Reference Card

Write these down — you will be asked about them in the presentation.

| Signal | PromQL Expression | Notes |
|---|---|---|
| **Latency p95** | `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))` | Use `le` label on histograms |
| **Traffic (RPS)** | `sum(rate(http_requests_total[5m]))` | Across all services |
| **Error Ratio** | `sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))` | 5xx / total |
| **CPU Saturation** | `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` | Invert idle time |
| **Memory Saturation** | `(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100` | Available not free |
| **Disk Saturation** | `(node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes * 100` | Per mountpoint |

---

## 4. Part 3 — SLOs & Error Budgets

### Your Goal

Turn the SLI expressions into formal reliability targets with calculated error budgets. Write the Error Budget Policy document.

### Error Budget Calculations

Work through these manually and document them in `slo/error-budget-policy.md`:

**30-day window = 43,200 minutes = 2,592,000 seconds**

| SLO | Target | Allowed Failures | Budget (minutes) |
|---|---|---|---|
| Availability | 99.5% | 0.5% of probes | 216 min downtime |
| Latency | 95% | 5% slow requests | 2,160 min of slow reqs |
| Error Rate | 99% | 1% errors | 432 min of error-rate violations |

### Error Budget Policy Document

Write `slo/error-budget-policy.md` with this content (expand as needed):

```markdown
# Error Budget Policy

## Owner
Engineering Lead (review monthly with PM)

## Measurement Window
Rolling 30 days

## Budget Thresholds & Responses

| Budget Consumed | Response |
|---|---|
| 0–25% | Normal operations. Features ship as usual. |
| 25–50% | Reliability review added to next sprint planning. |
| 50–75% | Feature velocity reduced by 20%. One reliability task per sprint mandatory. |
| 75–100% | Feature freeze. Full reliability sprint. |
| 100% (depleted) | No feature deployments until SLO met for 7 consecutive days. CTO sign-off required to lift freeze. |

## SLO Review
- Monthly cadence
- Changes require 30 days of SLI evidence and Engineering Lead + PM approval

## Budget Burn Alerts
See: prometheus/rules/slo-burn-rate.yml
- Fast Burn (critical): 14.4x burn rate — act in < 1 hour
- Slow Burn (warning): 5x burn rate — act before next sprint
```

### Grafana Error Budget Panels (Your Input)

Trojan builds these panels, but you define the thresholds and colour coding. Provide Trojan with:

1. The PromQL expressions for budget remaining (%).
2. The colour thresholds: green >50%, yellow 10–50%, red <10%.
3. The burn rate reference lines: 14.4x (critical) and 5x (warning).

**Budget Remaining PromQL:**

```promql
# Availability error budget remaining (%)
(
  1 - (
    1 - avg_over_time(probe_success{job="blackbox-http"}[30d])
  ) / (1 - 0.995)
) * 100

# Error rate error budget remaining (%)
(
  1 - (
    sum(rate(http_requests_total{status=~"5.."}[30d]))
    / sum(rate(http_requests_total[30d]))
  ) / (1 - 0.99)
) * 100
```

---

## 5. Part 7 — Incident Management & Runbooks

### Your Goal

Write a Markdown runbook for every alert rule Trojan has defined (11 total). Also simulate and document one blameless Post-Incident Review (PIR).

### Runbook Template

Use this exact structure for every runbook file in `runbooks/`:

```markdown
# Runbook: [AlertName]

## What Is This Alert?
[1–2 sentence plain-English explanation.]

## Likely Causes
1. [Most likely cause]
2. [Second cause]
3. [Edge case]

## Investigation Steps
1. **Check current metric value**
   - Grafana: [link to panel]
   - PromQL: `[expression]`

2. **Inspect recent logs**
   - LogQL: `{instance="[affected host]"} |= "error"`

3. **Identify the cause**
   - [Specific command or query]

## Resolution
1. [Step 1]
2. [Step 2]
3. Verify resolution: `[PromQL or command]`

## Should I Roll Back?
- Roll back if: [condition]
- Patch forward if: [condition]

## Escalation
- Escalate to: [person/team]
- Escalate when: [condition — e.g., not resolved within 30 minutes]
```

### Runbooks to Write (11 Total)

| File | Alert | Key Info |
|---|---|---|
| `cpu-warning.md` | CPUWarning | >80% for 5m — likely runaway process or traffic spike |
| `cpu-critical.md` | CPUCritical | >90% for 10m — escalate if not resolved in 15m |
| `memory-warning.md` | MemoryWarning | >80% — check for memory leaks, zombie processes |
| `memory-critical.md` | MemoryCritical | >90% — OOM risk, restart service if needed |
| `disk-warning.md` | DiskWarning | >75% — clean logs, rotate files |
| `disk-critical.md` | DiskCritical | >90% — stop log ingest to Loki if needed |
| `host-down.md` | HostDown | Probe fails 2m — check network, container status |
| `slo-fast-burn.md` | SLOFastBurn | 14.4x burn — immediate action required |
| `slo-slow-burn.md` | SLOSlowBurn | 5x burn — must act before it becomes fast burn |
| `cfr-threshold-exceeded.md` | CFRThresholdExceeded | >10% deployments failing — investigate pipeline |
| `mttr-exceeded.md` | MTTRExceeded | Mean restore time >1hr — process or tooling issue |

### Post-Incident Review (PIR)

Write `incidents/pir-001-latency-spike.md` documenting the Scenario 2 Game Day exercise (latency injection).

**Required Sections:**

```markdown
# Post-Incident Review: Latency Spike — [Date]

## Incident Summary
- **Severity:** [P1/P2/P3]
- **Duration:** [start to resolution]
- **Impact:** [% of users affected, SLO breach yes/no]
- **Error Budget Consumed:** [X minutes / X%]

## Timeline
| Time | Event |
|---|---|
| T+0:00 | Latency injection started (tc netem) |
| T+0:03 | Latency SLI crosses 500ms threshold in Grafana |
| T+0:12 | SLOFastBurn alert fires in Prometheus |
| T+0:13 | Slack notification received in #DevOps-Alerts |
| T+0:15 | On-call engineer begins investigation |
| T+0:18 | Loki logs show timeout errors correlated to trace IDs |
| T+0:20 | Tempo trace identifies slow downstream dependency |
| T+0:22 | Latency injection removed |
| T+0:25 | SLI recovers, alert resolves in Slack |

## Root Cause
[Describe what caused the latency — artificial injection in this case.]

## Detection Gap
[What did monitoring miss? How long until detection? Could it be faster?]

## What Went Well
- [e.g., Burn rate alert fired quickly]
- [e.g., Trace correlation immediately identified the slow span]

## Action Items
| Item | Owner | Due Date |
|---|---|---|
| Add p99 latency alert rule | Trojan | [date] |
| Instrument downstream service | Pabby | [date] |
```

---

## 6. Grafana Dashboards You Own

You are responsible for two dashboards in `grafana/dashboards/`. Trojan builds the other three.

### Node Exporter Dashboard (`node-exporter.json`)

Required panels:

| Panel | Type | PromQL |
|---|---|---|
| CPU Total (%) | Time series | `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| CPU Per-Core | Time series | `100 - (rate(node_cpu_seconds_total{mode="idle"}[5m]) * 100)` by cpu |
| Memory Used | Time series | `node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes` |
| Memory Breakdown | Bar gauge | Used / Cached / Available |
| Disk I/O Read | Time series | `rate(node_disk_read_bytes_total[5m])` |
| Disk I/O Write | Time series | `rate(node_disk_written_bytes_total[5m])` |
| Network In | Time series | `rate(node_network_receive_bytes_total[5m])` |
| Network Out | Time series | `rate(node_network_transmit_bytes_total[5m])` |
| Load Average | Stat | `node_load1`, `node_load5`, `node_load15` |

### Blackbox Exporter Dashboard (`blackbox-exporter.json`)

Required panels:

| Panel | Type | PromQL |
|---|---|---|
| Uptime Timeline | State timeline | `probe_success` |
| HTTP Response p50 | Time series | `histogram_quantile(0.50, rate(probe_http_duration_seconds_bucket[5m]))` |
| HTTP Response p90 | Time series | `histogram_quantile(0.90, ...)` |
| HTTP Response p99 | Time series | `histogram_quantile(0.99, ...)` |
| SSL Expiry Countdown | Stat | `probe_ssl_earliest_cert_expiry - time()` (in days) |
| Probe Success Rate | Gauge | `avg(avg_over_time(probe_success[24h]))` |

**To build dashboards as JSON:** Create panels in Grafana UI in a local dev environment, then export via `Dashboard → Share → Export JSON` and commit the file. Never save changes to the production Grafana instance via the UI.

---

## 7. Presentation Slides — Your Sections

When presenting, you cover these topics:

### Slide Set 1 — LGTM Architecture & Data Flow (3–4 slides)
- Architecture diagram (see main-doc.md Section 2).
- Walk through the data flow: metrics → logs → traces → Grafana.
- Explain why each component exists and what it replaces.
- Show the one-command deployment and the target verification table.

### Slide Set 2 — Four Golden Signals & SLI PromQL (4–5 slides)
- Define each signal in plain English.
- Show the PromQL expression for each.
- Explain why each signal matters more than raw CPU/RAM.
- Live demo: run each PromQL in Prometheus UI.

### Slide Set 3 — SLO Targets, Error Budgets & Budget Policy (3–4 slides)
- Show the SLO table with targets and rationale.
- Walk through one error budget calculation live.
- Explain burn rate (the "at this rate, when does my budget run out?" concept).
- Read out two thresholds from the Error Budget Policy.

### Slide Set 4 — Runbook Read-Aloud (1 slide)
- Pick `slo-fast-burn.md` and read it aloud in full.
- Explain each section — what, why, how, escalation.

### Slide Set 5 — Post-Incident Review (2 slides)
- Walk through the PIR timeline.
- Read one action item and explain who owns it.

---

## 8. Blog Post — Your Sections

Write these sections for the team blog post:

1. **"Why we chose the LGTM stack over managed alternatives"** — Use the comparison table from main-doc.md Section 1. Add your own cost and data sovereignty perspective.

2. **"The philosophy behind SLIs, SLOs, and Error Budgets"** — Explain the shift from "is it up?" to "is it reliable enough?" Cover the Google SRE Book origin, the error budget as a product conversation tool.

3. **"How the Four Golden Signals go beyond CPU and RAM"** — Use the PromQL expressions as examples. Show a real screenshot from Prometheus UI with your SLI expression running.

4. **Screenshots required from you:**
   - All LGTM components running (Prometheus targets page showing all UP).
   - SLO definitions YAML file in the repo.
   - Node Exporter dashboard.
   - Blackbox Exporter dashboard with SSL expiry countdown visible.
   - A runbook open in GitHub, showing the full Markdown structure.
   - PIR document open in GitHub.

---

## 9. Checklist

Use this to track your progress. Tick off each item as you complete it.

### Infrastructure (Part 1)
- [ ] `scripts/install.sh` written — creates users and directories
- [ ] `scripts/verify.sh` written — health checks all 8 services
- [ ] systemd unit files written for all 8 services (in `systemd/`)
- [ ] `prometheus.yml` with correct scrape configs (15s interval, `localhost` targets)
- [ ] `loki-config.yml` with 30-day retention
- [ ] `tempo-config.yml` with 7-day retention
- [ ] `otel-collector-config.yml` routing logs → Loki and traces → Tempo
- [ ] Terraform `main.tf` with bootstrap + all 8 modules
- [ ] Each Terraform module: downloads binary, writes config, installs + enables systemd unit
- [ ] `terraform apply` completes without errors
- [ ] One service instrumented with OpenTelemetry (traces emitted)
- [ ] Trace IDs embedded in log output
- [ ] All Prometheus targets show UP after apply

### Four Golden Signals (Part 2)
- [ ] `slo/slo-definitions.yml` written with 4 SLIs
- [ ] PromQL verified in Prometheus UI for each signal
- [ ] Can explain each signal in plain English without notes

### SLOs & Error Budgets (Part 3)
- [ ] SLO targets documented in `slo-definitions.yml`
- [ ] Error budget calculations done manually (show your working)
- [ ] `slo/error-budget-policy.md` written with all 5 budget thresholds
- [ ] Burn rate thresholds provided to Trojan (14.4x fast, 5x slow)

### Grafana Dashboards
- [ ] `grafana/dashboards/node-exporter.json` — all 9 panels present
- [ ] `grafana/dashboards/blackbox-exporter.json` — all 6 panels present
- [ ] Both dashboards load correctly in Grafana after provisioning

### Runbooks & Incident Management (Part 7)
- [ ] All 11 runbook Markdown files written
- [ ] Each runbook has: what, causes, 3 investigation steps, resolution, rollback decision, escalation
- [ ] `incidents/pir-001-latency-spike.md` written with all sections
- [ ] PIR has concrete action items with owners and due dates

### Presentation
- [ ] LGTM architecture slides ready (with diagram)
- [ ] Four Golden Signals slides with live PromQL demo
- [ ] SLO & error budget slides with live calculation
- [ ] Runbook read-aloud prepared (`slo-fast-burn.md`)
- [ ] PIR walkthrough prepared

### Blog Post
- [ ] "Why LGTM stack" section written
- [ ] "SLI/SLO/Error Budget philosophy" section written
- [ ] "Four Golden Signals" section written
- [ ] All required screenshots taken

---

*Pabby — ask Trojan for the alert rule YAML files (`prometheus/rules/`) so your runbooks reference the correct alert names and thresholds.*

*Last updated: May 2026*

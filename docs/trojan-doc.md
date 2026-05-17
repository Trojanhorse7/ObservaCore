# Trojan's Task Breakdown
## Observability Platform — DevOps Stage 6

> **Engineer:** Trojan  
> **Partner:** Pabby  
> **Full project reference:** [main-doc.md](./main-doc.md)

---

## Overview of Your Responsibilities

You own the **observability intelligence layer** of this platform — what the data *means*, how it is *displayed*, how *alerts* fire, and how the team *responds*. While Pabby builds and configures the underlying stack, you are responsible for turning raw telemetry into actionable insight.

Your work is split across four areas:

| Area | Parts Covered | Deliverables |
|---|---|---|
| DORA Metrics & CI/CD Observability | Part 4 | GitHub Actions integration, DORA PromQL, pipeline alerts |
| Grafana Dashboards (3 of 5) | Part 5 | DORA dashboard, SLO/Error Budget dashboard, Unified Observability dashboard |
| Full Alerting System | Part 6 | Alert rules YAML, Alertmanager config, Slack templates, inhibition rules |
| Game Day: Chaos Scenarios | Part 8 | All 3 scenarios executed, documented, and screenshotted |

---

## Table of Contents

1. [Your Files & Ownership Map](#1-your-files--ownership-map)
2. [Part 4 — DORA Metrics & CI/CD Observability](#2-part-4--dora-metrics--cicd-observability)
3. [Part 5 — Grafana Dashboards (Your Three)](#3-part-5--grafana-dashboards-your-three)
4. [Part 6 — The Full Alerting System](#4-part-6--the-full-alerting-system)
5. [Part 8 — Game Day: Chaos & Failure Simulation](#5-part-8--game-day-chaos--failure-simulation)
6. [Toil Identification — Your Section](#6-toil-identification--your-section)
7. [Presentation Slides — Your Sections](#7-presentation-slides--your-sections)
8. [Blog Post — Your Sections](#8-blog-post--your-sections)
9. [Checklist](#9-checklist)

---

## 1. Your Files & Ownership Map

You are the primary author of the following files.

```
observability-platform/
│
├── prometheus/
│   └── rules/
│       ├── infrastructure.yml          ← YOU own this
│       ├── slo-burn-rate.yml           ← YOU own this
│       └── cicd.yml                    ← YOU own this
│
├── alertmanager/
│   ├── alertmanager.yml                ← YOU own this
│   └── templates/
│       └── slack.tmpl                  ← YOU own this
│
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yml         ← YOU own this
│   │   └── dashboards/
│   │       └── dashboards.yml          ← YOU own this
│   └── dashboards/
│       ├── dora-metrics.json           ← YOU own this
│       ├── slo-error-budget.json       ← YOU own this
│       └── unified-observability.json  ← YOU own this
│
├── game-day/
│   ├── scenario-1-deployment-failure.md  ← YOU own this
│   ├── scenario-2-latency-injection.md   ← YOU own this
│   └── scenario-3-resource-pressure.md   ← YOU own this
│
└── README.md   ← SHARED (you write alerting, DORA, and Game Day sections)
```

---

## 2. Part 4 — DORA Metrics & CI/CD Observability

### Your Goal

Connect GitHub Actions to Prometheus, write the four DORA PromQL expressions, and configure alerts that fire when CFR or MTTR breach your SLO thresholds.

### Step 1 — GitHub Actions Integration

Add the following step to your deployment workflow. It pushes metrics to Pushgateway immediately after a deployment completes:

```yaml
# .github/workflows/deploy.yml

name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Record commit timestamp
        id: timestamps
        run: |
          echo "commit_ts=$(git log -1 --format=%ct)" >> $GITHUB_OUTPUT
          echo "trigger_ts=$(date +%s)" >> $GITHUB_OUTPUT

      - name: Run deployment
        id: deploy
        run: |
          # Your actual deploy command here
          echo "deploy_ts=$(date +%s)" >> $GITHUB_OUTPUT
          echo "result=success" >> $GITHUB_OUTPUT

      - name: Push DORA metrics to Pushgateway
        if: always()
        env:
          PUSHGATEWAY_URL: ${{ secrets.PUSHGATEWAY_URL }}
          DEPLOY_RESULT: ${{ steps.deploy.outputs.result || 'failure' }}
          COMMIT_TS: ${{ steps.timestamps.outputs.commit_ts }}
          TRIGGER_TS: ${{ steps.timestamps.outputs.trigger_ts }}
          DEPLOY_TS: ${{ steps.deploy.outputs.deploy_ts }}
          WORKFLOW_NAME: ${{ github.workflow }}
          RUN_ID: ${{ github.run_id }}
        run: |
          LEAD_TIME=$(( $DEPLOY_TS - $COMMIT_TS ))
          PIPELINE_DURATION=$(( $DEPLOY_TS - $TRIGGER_TS ))

          cat <<EOF | curl --silent --data-binary @- \
            "${PUSHGATEWAY_URL}/metrics/job/github_actions/instance/${GITHUB_RUN_ID}"
          # HELP github_actions_deployments_total Total deployments by result
          # TYPE github_actions_deployments_total counter
          github_actions_deployments_total{environment="production",result="${DEPLOY_RESULT}",workflow="${WORKFLOW_NAME}"} 1

          # HELP github_actions_lead_time_seconds Commit to deploy duration
          # TYPE github_actions_lead_time_seconds gauge
          github_actions_lead_time_seconds{workflow="${WORKFLOW_NAME}"} ${LEAD_TIME}

          # HELP github_actions_pipeline_duration_seconds Pipeline execution time
          # TYPE github_actions_pipeline_duration_seconds gauge
          github_actions_pipeline_duration_seconds{workflow="${WORKFLOW_NAME}"} ${PIPELINE_DURATION}
          EOF
```

**Required GitHub Actions secret:** `PUSHGATEWAY_URL` — set this to `http://<your-server-public-ip>:9091` in the repository Settings → Secrets and variables. The Pushgateway runs as a systemd service on the same host as the rest of the stack, installed by Pabby's Terraform setup.

### Step 2 — DORA PromQL Expressions

#### Deployment Frequency

```promql
# Deployments in last 24 hours
increase(github_actions_deployments_total{environment="production"}[24h])

# Classification logic (used in Grafana stat panel)
# Elite: > 1 per day → value > 1
# High: between 1/day and 1/week → value between 0.14 and 1
# Medium: between 1/week and 1/month → value between 0.033 and 0.14
# Low: < 1/month → value < 0.033
rate(github_actions_deployments_total{environment="production"}[7d]) * 86400
```

#### Lead Time for Changes

```promql
# Average LTC in hours
avg(github_actions_lead_time_seconds) / 3600

# P50 LTC
quantile(0.50, github_actions_lead_time_seconds) / 3600

# Pipeline duration (commit → pipeline complete)
avg(github_actions_pipeline_duration_seconds) / 60
```

#### Change Failure Rate

```promql
# Rolling 7-day CFR (percentage)
(
  sum(increase(github_actions_deployments_total{result=~"failure|rollback|hotfix"}[7d]))
  /
  sum(increase(github_actions_deployments_total[7d]))
) * 100

# Raw count of failed deployments this week
sum(increase(github_actions_deployments_total{result=~"failure|rollback|hotfix"}[7d]))
```

#### Mean Time to Restore

MTTR requires tracking when an incident starts (alert fires) and when it ends (alert resolves). Track this via a custom metric pushed when incidents are resolved:

```promql
# Average MTTR in minutes
avg(github_actions_incident_duration_seconds) / 60

# P90 MTTR
histogram_quantile(0.90,
  sum(rate(github_actions_incident_duration_seconds_bucket[30d])) by (le)
) / 60
```

### Step 3 — DORA Classification Logic

Use Grafana value mappings on the Deployment Frequency stat panel:

| Condition | Classification | Colour |
|---|---|---|
| Daily rate ≥ 1.0 | Elite | Green |
| Daily rate 0.14–1.0 | High | Blue |
| Daily rate 0.033–0.14 | Medium | Yellow |
| Daily rate < 0.033 | Low | Red |

Configure value mappings in the Grafana panel JSON under `fieldConfig.defaults.mappings`.

### Step 4 — CI/CD Alert Rules

Write `prometheus/rules/cicd.yml` (see full config in `main-doc.md` Section 10.3). Key rules:

```yaml
groups:
  - name: cicd
    rules:
      - alert: CFRThresholdExceeded
        expr: |
          (
            sum(increase(github_actions_deployments_total{result=~"failure|rollback|hotfix"}[7d]))
            / sum(increase(github_actions_deployments_total[7d]))
          ) * 100 > 10
        for: 10m
        labels:
          severity: critical
          service: cicd
        annotations:
          summary: "Change Failure Rate is {{ $value | printf \"%.1f\" }}% — exceeds 10% SLO"
          description: "More than 10% of deployments in the past 7 days resulted in failure, rollback, or hotfix."
          dashboard_url: "http://localhost:3000/d/dora-metrics"
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/cfr-threshold-exceeded.md"

      - alert: MTTRExceeded
        expr: avg(github_actions_incident_duration_seconds) / 60 > 60
        for: 5m
        labels:
          severity: warning
          service: cicd
        annotations:
          summary: "MTTR is {{ $value | printf \"%.0f\" }} minutes — exceeds 60-minute SLO"
          runbook_url: "https://github.com/yourorg/observability-platform/blob/main/runbooks/mttr-exceeded.md"
```

---

## 3. Part 5 — Grafana Dashboards (Your Three)

You build three of the five dashboards. Pabby builds Node Exporter and Blackbox Exporter.

**Rule:** Build all panels in a local Grafana dev instance, export as JSON, commit the file. Never save dashboard changes to the production Grafana via the UI.

### Dashboard 1 — DORA Metrics (`dora-metrics.json`)

#### Required Panels

| Panel | Type | Data |
|---|---|---|
| Deployment Frequency | Stat + classification badge | DF PromQL + value mappings |
| DF Trend (30 days) | Time series | Daily deployment count |
| Lead Time for Changes | Stat (hours) | Average LTC |
| LTC Sub-intervals | Bar chart | Commit→Trigger, Trigger→Complete, Complete→Deploy |
| Change Failure Rate | Gauge | CFR % with colour thresholds |
| CFR Trend | Time series | Rolling 7-day CFR |
| Mean Time to Restore | Stat (minutes) | Average MTTR |
| MTTR Distribution | Histogram | MTTR distribution per incident |
| DORA Performance Band | Table | All 4 metrics + classification column |

#### Classification Panel Design

The DORA Performance Band table must show:

```
| Metric | Current Value | Classification | Trend |
|---|---|---|---|
| Deployment Frequency | 3.2/day | 🟢 Elite | ↑ |
| Lead Time | 45 min | 🟢 Elite | → |
| Change Failure Rate | 4.2% | 🟢 Elite | ↓ |
| MTTR | 18 min | 🟢 Elite | ↓ |
```

Use Grafana Transformations (`Add field from calculation` + `Organize fields`) to produce this table from individual stat queries.

### Dashboard 2 — SLO & Error Budget (`slo-error-budget.json`)

Get SLI expressions and thresholds from Pabby (`slo/slo-definitions.yml`). You build the visualisation.

#### Required Panels

| Panel | Type | Details |
|---|---|---|
| Availability SLI vs SLO | Gauge | Current value vs 99.5% target |
| Latency SLI vs SLO | Gauge | Current vs 95% target |
| Error Rate SLI vs SLO | Gauge | Current vs 99% target |
| Error Budget Remaining (%) | Bar gauge | Green >50%, yellow 10–50%, red <10% |
| Error Budget Remaining (minutes) | Stat | Absolute minutes left per SLO |
| Burn Rate Time Series | Time series | Current burn rate with 14.4x and 5x reference lines |
| SLO Compliance 7-day | Stat | Pass/Fail |
| SLO Compliance 30-day | Stat | Pass/Fail |
| Budget History | Time series | Budget remaining over last 30 days |

#### Burn Rate Reference Lines Panel

In the time series panel JSON, add constant threshold lines:

```json
"thresholds": {
  "mode": "absolute",
  "steps": [
    {"color": "green", "value": null},
    {"color": "yellow", "value": 5},
    {"color": "red", "value": 14.4}
  ]
}
```

### Dashboard 3 — Unified Observability (`unified-observability.json`)

**This is the most critical dashboard.** The drill-down flow must work end-to-end.

#### Required Panels

| Panel | Type | Purpose |
|---|---|---|
| Error Rate Time Series | Time series | Metric spike — entry point for investigation |
| P99 Latency | Time series | Latency spike — entry point |
| Request Volume | Time series | Traffic context |
| Recent Errors Log Panel | Logs | Loki query — shows correlated logs |
| Trace Search | Traces | Tempo query — shows recent traces |
| Service Map | Node graph | Service dependency map (from Tempo) |

#### Drill-Down Configuration

**Step 1 — Panel Links on Error Rate Panel:**

```json
"links": [
  {
    "title": "Explore in Loki",
    "url": "/explore?left={\"datasource\":\"loki\",\"queries\":[{\"expr\":\"{service_name=\\\"$service\\\"} |= \\\"error\\\"\",\"refId\":\"A\"}],\"range\":{\"from\":\"${__from}\",\"to\":\"${__to}\"}}"
  }
]
```

**Step 2 — Derived Fields in Loki Datasource (set by Pabby in `datasources.yml`):**

This is already configured by Pabby. Verify it works by:
1. Opening the Loki Explore view.
2. Running `{service_name="your-service"} |= "error"`.
3. Expanding a log line containing `traceID=`.
4. Confirming the trace ID appears as a clickable link labelled "Open in Tempo".

**Step 3 — Tempo to Loki Link (configured in datasource):**

```yaml
# In datasources.yml (Pabby's file — coordinate with them)
tracesToLogs:
  datasourceUid: loki
  tags: ['service.name']
  lokiSearch: true
```

**Step 4 — Acceptance Criterion Walkthrough**

Before submitting, walk through this flow and screenshot each step:

1. Open Unified Observability dashboard.
2. Inject an error or use Game Day Scenario 2 to create a spike.
3. Screenshot the error rate spike in the panel.
4. Click "Explore in Loki" link on the panel.
5. Screenshot Loki logs showing `traceID=` field highlighted as a link.
6. Click the trace ID link.
7. Screenshot Tempo showing the full trace waterfall with the slow/failing span highlighted.
8. Screenshot the span detail showing the service name, operation, and duration.

### Grafana Provisioning Files (Your Responsibility)

```yaml
# grafana/provisioning/datasources/datasources.yml
# All services run on the same host as Grafana (systemd, no Docker networking)
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus
    url: http://localhost:9090
    isDefault: true
    jsonData:
      timeInterval: "15s"

  - name: Loki
    type: loki
    uid: loki
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
    uid: tempo
    url: http://localhost:3200
    jsonData:
      tracesToLogs:
        datasourceUid: loki
        tags: ['service.name', 'instance']
        lokiSearch: true
      serviceMap:
        datasourceUid: prometheus
      search:
        hide: false
```

```yaml
# grafana/provisioning/dashboards/dashboards.yml
apiVersion: 1
providers:
  - name: default
    orgId: 1
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: false
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
```

---

## 4. Part 6 — The Full Alerting System

### Your Goal

Write all alert rule YAML files, configure Alertmanager with route trees and inhibition rules, and create the structured Slack template. Every alert must link to a runbook (Pabby writes the runbook content — you write the alert that links to it).

### Step 1 — Infrastructure Alert Rules

Write `prometheus/rules/infrastructure.yml`. See the full config in `main-doc.md` Section 10.1.

**Summary of rules to implement:**

| Alert | Condition | `for` | Severity |
|---|---|---|---|
| CPUWarning | CPU > 80% | 5m | warning |
| CPUCritical | CPU > 90% | 10m | critical |
| MemoryWarning | RAM > 80% | 5m | warning |
| MemoryCritical | RAM > 90% | 5m | critical |
| DiskWarning | Disk > 75% | 5m | warning |
| DiskCritical | Disk > 90% | 5m | critical |
| HostDown | `probe_success == 0` | 2m | critical |

**Critical rule about `for` durations:** Every rule must have a `for:` field. This prevents flapping — transient spikes do not fire alerts. The duration must be long enough to confirm a real problem but short enough to still be actionable.

### Step 2 — SLO Burn Rate Alert Rules

Write `prometheus/rules/slo-burn-rate.yml`. See full config in `main-doc.md` Section 10.2.

**Multi-window burn rate explanation (important for presentation):**

The dual-window approach (e.g., checking both `[1h]` and `[5m]`) prevents false positives from short spikes:
- The **long window** (1h) confirms the burn rate is sustained.
- The **short window** (5m) confirms it is still happening right now.
- Both must be true for the alert to fire.

```yaml
# Both conditions must be true (use `and` in PromQL)
(long_window_burn_rate > threshold)
and
(short_window_burn_rate > threshold)
```

| Alert | Burn Rate | Windows | `for` | Severity |
|---|---|---|---|---|
| SLOFastBurn | > 14.4x | 1h + 5m | 2m | critical |
| SLOSlowBurn | > 5x | 6h + 30m | 15m | warning |

### Step 3 — Alertmanager Configuration

Write `alertmanager/alertmanager.yml`. See full config in `main-doc.md` Section 10.4.

Key configuration decisions to document:

**Route Tree:**
```
root receiver: slack-devops-alerts
├── severity=critical → repeat every 1h
└── severity=warning  → repeat every 4h
```

**Inhibition Rule:** When `HostDown` fires for an instance, suppress all `CPU*`, `Memory*`, `Disk*`, and `SLO*` alerts for the same instance. This prevents alert storms when a host is fully unreachable.

```yaml
inhibit_rules:
  - source_match:
      alertname: HostDown
    target_match_re:
      alertname: 'CPU.*|Memory.*|Disk.*|SLO.*'
    equal: ['instance']
```

**Document the silence configuration:** Alertmanager silences can be created via the UI at `http://localhost:9093` or via API:

```bash
# Create a 2-hour maintenance silence via API
curl -X POST http://localhost:9093/api/v1/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [{"name": "instance", "value": "your-host:9100", "isRegex": false}],
    "startsAt": "2026-05-16T22:00:00Z",
    "endsAt": "2026-05-17T00:00:00Z",
    "comment": "Planned maintenance",
    "createdBy": "trojan"
  }'
```

### Step 4 — Structured Slack Template

Write `alertmanager/templates/slack.tmpl`. See the full template in `main-doc.md` Section 10.5.

**Key requirements:**
- Every alert payload must include: alert name, severity, host, current metric value, Grafana dashboard link, runbook link, firing/resolved status, and timestamp.
- Plain text is not acceptable — use the structured template format.
- Test with a manual alert:

```bash
# Manually trigger a test alert to verify Slack delivery
curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning",
      "instance": "test-host:9100"
    },
    "annotations": {
      "summary": "This is a test alert",
      "runbook_url": "https://github.com/yourorg/observability-platform/blob/main/runbooks/cpu-warning.md",
      "dashboard_url": "http://grafana:3000"
    }
  }]'
```

### Step 5 — Verify All Alert Rules Load

After writing the YAML files, verify Prometheus loads them without errors:

```bash
# Validate YAML syntax with promtool before deploying
# (promtool is installed alongside prometheus by Pabby's Terraform module)
promtool check rules prometheus/rules/infrastructure.yml
promtool check rules prometheus/rules/slo-burn-rate.yml
promtool check rules prometheus/rules/cicd.yml

# Reload Prometheus to pick up new rules (requires --web.enable-lifecycle)
curl -X POST http://localhost:9090/-/reload

# Verify rules loaded correctly
curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool | grep '"name"'
```

---

## 5. Part 8 — Game Day: Chaos & Failure Simulation

### Your Goal

Execute all three scenarios, document the full timeline, take screenshots at every step, and write the scenario reports in `game-day/`.

### Scenario 1 — Deployment Failure

**File:** `game-day/scenario-1-deployment-failure.md`

**Preparation:** Coordinate with Pabby — they need the LGTM stack running and all services healthy before you begin.

**Steps:**

```bash
# Step 1: Introduce a deliberate syntax error
# Edit the Dockerfile to add an invalid instruction
echo "INVALID_INSTRUCTION" >> Dockerfile

# Step 2: Commit and push
git add Dockerfile
git commit -m "test: intentional failure for game day"
git push origin main

# Step 3: Watch GitHub Actions fail
# Screenshot: GitHub Actions UI showing failed workflow

# Step 4: Observe Pushgateway receives failure metric
curl http://localhost:9091/metrics | grep github_actions_deployments_total

# Step 5: Wait for alert evaluation (10m for rule, then fires)
# Screenshot: Prometheus UI showing CFRThresholdExceeded in PENDING then FIRING

# Step 6: Screenshot Slack notification in #DevOps-Alerts
# Screenshot: DORA dashboard showing CFR spike

# Step 7: Fix and recover
git revert HEAD
git push origin main
# Screenshot: Resolved alert in Slack
```

**Document in your report:**

| Time | Event |
|---|---|
| T+0:00 | Bad commit pushed |
| T+0:XX | Pipeline fails |
| T+0:XX | Failure metric received by Pushgateway |
| T+0:XX | Alert enters PENDING |
| T+0:XX | Alert FIRES — Slack notified |
| T+0:XX | Fix pushed |
| T+0:XX | RESOLVED appears in Slack |

### Scenario 2 — Latency Injection

**File:** `game-day/scenario-2-latency-injection.md`

**Steps:**

```bash
# Method A: Using tc netem (Linux traffic control)
# Inject 600ms latency on loopback
sudo tc qdisc add dev lo root netem delay 600ms

# Method B: Application-level (if you have a Flask/Express app)
# Add time.sleep(0.6) to a route handler

# Step 2: Watch latency SLI degrade in Grafana
# Screenshot: Latency panel crossing 500ms

# Step 3: Watch burn rate climb
# Screenshot: Burn rate time series crossing 14.4x

# Step 4: Confirm SLOFastBurn fires
# Screenshot: Alert firing in Prometheus UI

# Step 5: Screenshot Slack with full structured payload

# Step 6: Loki correlation
# Open Loki Explore, run: {service_name="your-service"} |= "error"
# Screenshot: Log lines with traceID= field shown as clickable link

# Step 7: Tempo drill-down
# Click trace ID link
# Screenshot: Tempo trace waterfall with slow span highlighted

# Step 8: Remove latency
sudo tc qdisc del dev lo root

# Screenshot: SLI recovering, alert resolving in Slack
```

**This scenario must demonstrate the complete drill-down path.** Get screenshots of all 8 steps listed in Dashboard 3 Section above.

### Scenario 3 — Resource Pressure

**File:** `game-day/scenario-3-resource-pressure.md`

**Steps:**

```bash
# Install stress tool
sudo apt-get install -y stress

# Step 1: Apply CPU pressure (push above 80% but below 90%)
stress --cpu 4 --timeout 400s &
STRESS_PID=$!

# Step 2: Wait 5+ minutes, confirm CPUWarning fires
# Screenshot: Warning alert in Slack (#DevOps-Alerts)

# Step 3: Increase pressure above 90%
stress --cpu 8 --timeout 300s

# Step 4: Wait 10+ minutes, confirm CPUCritical fires
# Screenshot: Critical alert in Slack — both warning AND critical visible

# Step 5: Kill stress process
kill $STRESS_PID
killall stress

# Step 6: Wait for CPU to normalise
# Screenshot: Both alerts resolve — ✅ RESOLVED messages in Slack

# Confirm inhibition rules work (bonus):
# While CPUCritical is firing, check Alertmanager UI
# Verify no duplicate noise alerts are routing through
```

**Key observation to document:** Warning fires BEFORE critical. Recovery RESOLVED messages arrive for both in Slack. The sequence proves the alert pipeline is working correctly.

---

## 6. Toil Identification — Your Section

In the final report and blog post, you cover the toil section alongside Pabby. You are responsible for identifying at least 2 examples and highlighting what was implemented.

### Your Toil Examples

| # | Toil | Time Cost | Automation | Status |
|---|---|---|---|---|
| 1 | Manually creating Grafana dashboards via UI after re-deploy | ~2 hrs | Grafana provisioning JSON + IaC | **Implemented by you** |
| 2 | Manually pushing deployment metrics to Pushgateway | ~5 min/deploy | GitHub Actions step in CI/CD workflow | **Implemented by you** |

**Be ready to speak to these in the presentation.** Explain what you automated, how you did it, and what the before/after looks like.

---

## 7. Presentation Slides — Your Sections

### Slide Set 1 — DORA Dashboard (3–4 slides)
- Show the live DORA dashboard with all 4 metrics visible.
- Explain the classification bands (Elite/High/Medium/Low) and what each means for a business.
- Walk through how GitHub Actions pushes data to Prometheus.
- Show the CFR alert rule YAML and explain the `for: 10m` threshold.

### Slide Set 2 — All Five Grafana Dashboards (5–6 slides)
- Walk through each dashboard — one slide per dashboard.
- For the Unified Observability dashboard, perform the live drill-down: metric spike → Loki logs → Tempo trace → root cause.
- This is the technical highlight of the presentation — practise it until it is fluent.

### Slide Set 3 — Alertmanager Routing & Slack Templates (3 slides)
- Show the route tree diagram.
- Explain the inhibition rule (HostDown suppresses CPU/memory noise).
- Show a live Slack notification in #DevOps-Alerts with all fields visible.
- Explain why structured templates are better than plain text.

### Slide Set 4 — Burn Rate Alerting (2 slides)
- Explain burn rate vs threshold alerting — the "at this rate, when does budget run out?" framing.
- Show the dual-window PromQL logic.
- Explain why this reduces alert fatigue.

### Slide Set 5 — Game Day Results (3 slides)
- One slide per scenario: what you did, what fired, what you observed.
- Show the screenshot sequence for Scenario 2 (latency → trace drill-down).
- Discuss what you would improve based on what you observed.

---

## 8. Blog Post — Your Sections

Write these sections for the team blog post:

1. **"How DORA metrics connect to business outcomes"** — Explain why DF, LTC, CFR, and MTTR are business metrics disguised as engineering metrics. Link DF to competitive advantage. Link MTTR to revenue loss per hour of downtime.

2. **"How burn rate alerting reduces alert fatigue"** — Explain the problem with threshold alerts (noise, missing context). Show the math behind burn rate. Explain why an alert that says "you will breach your SLO in 2 hours" is more actionable than "error rate is 2.1%".

3. **"Game Day: what we broke and what we learned"** — Cover all 3 scenarios. Include screenshots of the Slack notifications (firing and resolved). Discuss the MTTR you observed vs your SLO target.

4. **"Toil we identified and automated"** — Your two toil examples with before/after.

5. **Screenshots required from you:**
   - DORA Metrics dashboard (all 4 panels visible, with classification badges).
   - SLO & Error Budget dashboard (burn rate time series with reference lines).
   - Unified Observability dashboard (drill-down at each step).
   - Alert rules YAML file open in the repository.
   - Alertmanager routing config showing inhibition rules.
   - Slack #DevOps-Alerts channel showing at least one firing and one resolved notification.
   - All three Game Day scenarios: trigger → degradation → alert → (Scenario 2: trace) → recovery.

---

## 9. Checklist

### DORA Metrics (Part 4)
- [ ] GitHub Actions workflow updated with Pushgateway metric step
- [ ] `PUSHGATEWAY_URL` secret added to GitHub repository
- [ ] DF PromQL returns data in Prometheus UI
- [ ] LTC PromQL returns data in Prometheus UI
- [ ] CFR PromQL returns data in Prometheus UI
- [ ] `prometheus/rules/cicd.yml` written with CFR and MTTR alerts
- [ ] DORA classification thresholds defined

### Grafana Dashboards (Part 5)
- [ ] `grafana/provisioning/datasources/datasources.yml` written
- [ ] `grafana/provisioning/dashboards/dashboards.yml` written
- [ ] `grafana/dashboards/dora-metrics.json` — all 9 panels
- [ ] `grafana/dashboards/slo-error-budget.json` — all 9 panels
- [ ] `grafana/dashboards/unified-observability.json` — all 6 panels + drill-down
- [ ] Loki derived field → Tempo link working end-to-end
- [ ] All dashboards load from provisioning (no manual UI creation)

### Alerting System (Part 6)
- [ ] `prometheus/rules/infrastructure.yml` — all 7 rules
- [ ] `prometheus/rules/slo-burn-rate.yml` — fast burn + slow burn (dual-window)
- [ ] `prometheus/rules/cicd.yml` — CFR + MTTR alerts
- [ ] `alertmanager/alertmanager.yml` — route tree + inhibition rules
- [ ] `alertmanager/templates/slack.tmpl` — structured template
- [ ] All rules validated with `promtool check rules`
- [ ] Alertmanager routes confirmed working (test alert sent)
- [ ] Slack notification received with all required fields

### Game Day (Part 8)
- [ ] Scenario 1: Deployment failure executed, timeline documented, screenshots taken
- [ ] Scenario 2: Latency injection executed, full drill-down path screenshotted
- [ ] Scenario 3: Resource pressure executed, warning before critical confirmed, recovery confirmed
- [ ] All 3 `game-day/*.md` reports written

### Presentation
- [ ] DORA dashboard live demo prepared
- [ ] All 5 dashboards walkthrough prepared
- [ ] Live drill-down (Unified Observability) practised and fluent
- [ ] Alertmanager routing and Slack template slides ready
- [ ] Burn rate alerting explanation prepared
- [ ] Game Day results slides with screenshots

### Blog Post
- [ ] "DORA and business outcomes" section written
- [ ] "Burn rate alerting reduces fatigue" section written
- [ ] "Game Day findings" section written
- [ ] "Toil automation" section written
- [ ] All required screenshots taken and labelled

---

*Trojan — coordinate with Pabby on two critical handoffs: (1) get the SLO definitions from `slo/slo-definitions.yml` before building the SLO dashboard, (2) share the alert rule names so Pabby can write matching runbooks.*

*Last updated: May 2026*

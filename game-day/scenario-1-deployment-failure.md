# Game Day — Scenario 1: Deployment Failure

**Date:** ___________  
**Executed by:** Trojan  
**Objective:** Confirm that a failing GitHub Actions deployment updates DORA metrics, fires the `CFRThresholdExceeded` alert in Slack, and that the full structured payload is received.

---

## Pre-Conditions

Before starting, confirm all services are healthy:

```bash
systemctl is-active prometheus loki tempo grafana-server alertmanager
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:3100/ready
```

- [ ] All services active
- [ ] Prometheus targets all UP at `http://localhost:9090/targets`
- [ ] DORA Metrics dashboard loading at `http://localhost:3000/d/dora-metrics`
- [ ] #DevOps-Alerts Slack channel is open and being monitored

---

## Steps

### Step 1 — Introduce a deliberate failure

Add a syntax error to the deployment workflow to guarantee pipeline failure.

```bash
# In the repository root
echo "INVALID_YAML_SYNTAX: [[[" >> .github/workflows/deploy.yml
git add .github/workflows/deploy.yml
git commit -m "test(game-day): deliberate failure for scenario 1"
git push origin main
```

**Screenshot:** GitHub Actions run showing the failed workflow in red.  
**Timestamp:** ___________

---

### Step 2 — Verify the failure metric reaches Pushgateway

The `deploy.yml` workflow pushes metrics even on failure (`if: always()`).

```bash
# Check Pushgateway for the failure metric
curl -s http://localhost:9091/metrics | grep github_actions_deployments_total

# Expected output contains: result="failure"
# github_actions_deployments_total{...,result="failure",...} 1
```

**Screenshot:** Terminal output showing the failure metric.  
**Timestamp:** ___________

---

### Step 3 — Watch Prometheus evaluate the CFR rule

```bash
# Check the current CFR value
curl -s 'http://localhost:9090/api/v1/query?query=cicd:deployment_failure_rate:ratio7d*100' \
  | python3 -m json.tool

# Watch for the alert entering PENDING
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool | grep -A5 "CFRThreshold"
```

The rule has `for: 10m` — check again after 10 minutes for FIRING status.

**Screenshot:** Prometheus UI → Alerts page showing `CFRThresholdExceeded` in PENDING then FIRING.  
**Timestamp (PENDING):** ___________  
**Timestamp (FIRING):** ___________

---

### Step 4 — Confirm Slack notification

Check the `#DevOps-Alerts` Slack channel.

**Expected payload fields:**
- Alert name: `CFRThresholdExceeded`
- Severity: `CRITICAL`
- Summary includes current CFR percentage
- Dashboard link to DORA Metrics
- Runbook link

**Screenshot:** Full Slack message with all fields visible.  
**Timestamp received:** ___________

---

### Step 5 — Observe DORA dashboard

Open `http://localhost:3000/d/dora-metrics`

- [ ] CFR gauge has moved above 10%
- [ ] CFR gauge colour has changed to red
- [ ] DORA classification has changed from Elite/High to Medium/Low
- [ ] CFR Trend panel shows the spike

**Screenshot:** DORA dashboard with CFR spike visible.

---

### Step 6 — Fix and recover

```bash
# Revert the bad commit
git revert HEAD --no-edit
git push origin main
```

Wait for the pipeline to succeed. The failure count is now offset by a success.

**Screenshot:** GitHub Actions run showing the fixed deployment in green.  
**Screenshot:** Prometheus alert moving back to inactive.  
**Screenshot:** Slack `✅ [RESOLVED]` notification.  
**Timestamp resolved:** ___________

---

## Timeline Summary

| Time | Event |
|---|---|
| T+0:00 | Bad commit pushed to main |
| T+0:XX | GitHub Actions workflow triggered |
| T+0:XX | Workflow fails — failure metric pushed to Pushgateway |
| T+0:XX | `CFRThresholdExceeded` enters PENDING in Prometheus |
| T+0:XX | Alert FIRES — Alertmanager routes to Slack |
| T+0:XX | Slack notification received in #DevOps-Alerts |
| T+0:XX | Fix pushed — pipeline succeeds |
| T+0:XX | RESOLVED notification in Slack |

---

## Observations

**What worked well:**
- 

**What was slower than expected:**
- 

**MTTR (alert fire to fix confirmed):** ___________

**Action items from this scenario:**
- 

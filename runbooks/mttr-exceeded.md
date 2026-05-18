# Runbook: MTTR Exceeded

**Alert:** `MTTRExceeded`
**Severity:** warning
**Dashboard:** http://localhost:3000/d/dora-metrics

---

## What is this alert?

**Mean Time to Restore (MTTR)** is the average time from when an incident is detected (alert fires) to when the service is restored to its SLO. The SLO target is **MTTR < 60 minutes**.

This alert fires when the average MTTR recorded over recent incidents has exceeded 60 minutes. This indicates the incident response process is slower than acceptable and manual steps are adding unnecessary delay.

### DORA MTTR benchmarks

| Classification | MTTR |
|---|---|
| Elite | < 1 hour |
| High | < 1 day |
| Medium | < 1 week |
| Low | > 1 week |

---

## Likely causes

- Manual investigation steps with no runbook guidance
- On-call engineer was not paged promptly (alert routing issue)
- Rollback procedure is undocumented or requires manual steps
- Service dependency takes a long time to recover (database, external API)
- Insufficient observability — root cause is hard to find without good traces/logs

---

## Investigation steps

**Step 1 — Review recent incident durations**

Check the [DORA dashboard](http://localhost:3000/d/dora-metrics) for the MTTR trend. Identify which specific incidents took longest.

```bash
# Query the raw MTTR metric
curl -g 'http://localhost:9090/api/v1/query?query=github_actions_incident_duration_seconds'
```

**Step 2 — Identify where time was spent**

For each slow incident, trace the timeline:
- Time from alert fire to first acknowledgement
- Time from acknowledgement to diagnosis
- Time from diagnosis to fix deployed
- Time from fix deployed to service restored

The longest segment reveals where to focus: alerting latency, runbook gaps, or deployment speed.

**Step 3 — Check alert routing**

Confirm Alertmanager is routing alerts correctly and Slack notifications are appearing in `#DevOps-Alerts` within 1–2 minutes of an alert firing.

```bash
# Check Alertmanager status
curl http://localhost:9093/api/v2/alerts
```

---

## Resolution

1. **If on-call response time is slow**: review the on-call rotation and ensure Slack notifications are visible. Consider a pager integration for critical alerts.

2. **If diagnosis is slow**: improve runbooks for the alerts that fired. Add Loki log queries and Tempo trace links to the runbook. Ensure unified dashboard drill-down is working.

3. **If deployment is slow**: pre-build deployment artefacts or use feature flags to enable instant rollback without a full pipeline run.

4. **If the metric itself is wrong**: verify that `github_actions_incident_duration_seconds` is being pushed correctly from the CI/CD pipeline after each incident resolution.

---

## Rollback decision

Not applicable — this alert is about response speed, not service state. The service may already be restored by the time this alert fires.

---

## Escalation

- Engineering lead should review the MTTR trend monthly
- If a single incident exceeded 4 hours, a blameless post-incident review is required
- Identify the specific manual steps that added the most time and automate them

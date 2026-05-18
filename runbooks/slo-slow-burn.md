# Runbook: SLO Slow Burn

**Alerts:** `SLOSlowBurn`, `AvailabilitySlowBurn`, `LatencySlowBurn`
**Severity:** warning
**Dashboard:** http://localhost:3000/d/slo-error-budget

---

## What is this alert?

A **slow burn** means the error budget is being consumed at a rate that, if sustained, will exhaust the monthly budget within the current window — but not immediately. Specifically:

- `SLOSlowBurn`: the error rate SLO is burning at **>5x** the sustainable rate over both the 6-hour and 30-minute windows. At this pace, **5% of the monthly error budget** will be consumed in 6 hours.
- `AvailabilitySlowBurn`: the availability SLO (probe success rate) is degraded at 5x burn over the 6-hour window.
- `LatencySlowBurn`: the latency SLO (requests under 500ms) is burning at 5x over 6 hours.

This alert exists to catch problems that are serious but not yet catastrophic — giving you time to investigate before it escalates to a fast burn.

---

## Likely causes

- A recent deployment introduced a regression that degrades a subset of requests
- A dependency (database, downstream service, CDN) is degraded but not completely down
- Traffic is gradually increasing and the service is approaching saturation
- A cron job or batch process is consuming resources periodically
- Memory leak or connection pool exhaustion that worsens over time

---

## Investigation steps

**Step 1 — Check the SLO dashboard**

Open the [SLO & Error Budget dashboard](http://localhost:3000/d/slo-error-budget). Identify:
- Which SLO is burning (error rate, availability, or latency)
- How much budget remains
- When the burn rate started increasing (time series graph)

**Step 2 — Correlate with recent deployments**

Check the [DORA dashboard](http://localhost:3000/d/dora-metrics) for deployments in the last 6–12 hours. If a deployment coincides with the burn start, it is the prime suspect.

```bash
# Check GitHub Actions recent runs
# Or query Prometheus for recent deployment activity
curl -g 'http://localhost:9090/api/v1/query?query=increase(github_actions_deployments_total[6h])'
```

**Step 3 — Drill into logs and traces**

Open the [Unified Observability dashboard](http://localhost:3000/d/unified-observability). Use the time range matching when the burn started:
- Switch to Loki and filter for `level=error` or `status=~"5.."`
- Click a trace ID in the log line to jump to Tempo
- Identify the slowest or most-failing spans

```logql
{job="observability-demo"} |= "error" | logfmt | status >= 500
```

---

## Resolution

1. If a deployment is responsible, evaluate rolling back: `git revert <sha>` and redeploy
2. If a dependency is degraded, check its status page or health endpoint and open an incident with that team
3. If it is a resource saturation issue, scale the service or shed load by temporarily rate-limiting non-critical endpoints
4. If it is a memory leak, restart the affected process and open a tracking issue

After resolving, confirm the burn rate drops below the threshold. The alert will auto-resolve when the condition clears for 15 minutes.

---

## Rollback decision

Roll back if: the slow burn started within 1 hour of a deployment AND the deployment is the only change. Do not roll back if the degradation predates the last deployment — investigate infrastructure instead.

---

## Escalation

- Assign an engineer to own this immediately
- If budget consumption exceeds 50% while investigating, treat as critical and page the on-call lead
- If no resolution in 2 hours, escalate to the engineering lead

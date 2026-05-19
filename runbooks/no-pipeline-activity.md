# Runbook: No Pipeline Activity

**Alert:** `NoPipelineActivity` (warning)
**Severity:** warning
**Dashboard:** http://localhost:3000/d/dora-metrics

---

## What is this alert?

No deployment metrics have been recorded in Prometheus via the Pushgateway for **7 days**. Either the CI/CD pipeline has genuinely stalled, or the metric push step in GitHub Actions is broken.

---

## Likely causes

- The `PUSHGATEWAY_URL` secret in GitHub Actions is missing, wrong, or the Pushgateway is unreachable from GitHub's runners
- The GitHub Actions workflow no longer includes the "Push DORA metrics" step (e.g. after a workflow file refactor)
- No deployments have genuinely run in 7 days (pipeline is paused or there is no activity)
- The Pushgateway service itself has crashed

---

## Investigation steps

**Step 1 — Check Pushgateway health**

```bash
systemctl is-active pushgateway
curl -s http://localhost:9091/metrics | grep github_actions_deployments
```

If the service is down: `sudo systemctl restart pushgateway`

**Step 2 — Check GitHub Actions**

Go to the repository → Actions tab. Look at recent workflow runs and confirm the "Push DORA metrics" step is present and passing. If it is failing, check the `PUSHGATEWAY_URL` secret:

- Settings → Secrets and variables → Actions → `PUSHGATEWAY_URL`
- Value should be `http://<server-ip>:9091`

**Step 3 — Verify metrics from Prometheus**

```bash
curl -g 'http://localhost:9090/api/v1/query?query=github_actions_deployments_total'
```

If no data is returned, the Pushgateway is not receiving pushes from GitHub Actions.

---

## Resolution

1. Fix the `PUSHGATEWAY_URL` secret in GitHub Actions if it is wrong
2. Re-run the most recent deployment workflow manually to force a metric push
3. Confirm the alert resolves within 5 minutes of a successful push

---

## Escalation

If no deployments have genuinely occurred in 7 days, notify the engineering lead — this may indicate a blocked or frozen release cycle.

# Runbook: High Change Failure Rate

## What is this alert?
More than 15% of deployments in the last 7 days have resulted in failures, rollbacks, or hotfixes. This exceeds the DORA CFR SLO threshold.

## Likely causes
- Insufficient testing before deployment
- Missing environment variable validation in CI pipeline
- No staging environment — deploying directly to production
- Lack of automated rollback mechanism

## First 3 investigation steps
1. Open the DORA dashboard and identify which deployments failed
2. Review the GitHub Actions logs for those deployments
3. Check if failures share a common pattern — same service, same time of day, same engineer

## Resolution
- Add integration tests to the CI pipeline
- Implement pre-deployment validation checks
- Add automatic rollback on health check failure

## Should I roll back?
This is a trend alert not an immediate incident. Focus on process improvement rather than rollback.

## Escalation
Escalate to engineering lead for process review if CFR remains above 15% for two consecutive weeks.

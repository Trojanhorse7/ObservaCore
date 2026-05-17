# Blameless Post-Incident Review

## Incident Title
High Error Rate — SLO Fast Burn Alert

## Date and Duration
- Date: 2026-05-16
- Duration: 14 minutes (14:32 to 14:46)

## Severity
Critical — SLO Fast Burn alert fired, 8% of monthly error budget consumed

## Incident Summary
A deployment of the demo-app service caused a 45% error rate for approximately 14 minutes, triggering the SLO Fast Burn alert and consuming 8% of the monthly error budget. The root cause was a missing environment variable that caused the application to fail on every affected request.

## Timeline

| Time  | Event |
|-------|-------|
| 14:32 | Deployment triggered via GitHub Actions |
| 14:33 | Error rate begins climbing — first 5xx responses observed |
| 14:35 | SLO Fast Burn alert fires in #DevOps-Alerts Slack channel |
| 14:36 | On-call engineer acknowledges the alert |
| 14:38 | Root cause identified — missing OTEL_EXPORTER_OTLP_ENDPOINT variable |
| 14:44 | Rollback initiated via systemctl restart with previous config |
| 14:46 | Error rate returns to baseline |
| 14:47 | Resolved alert fires in #DevOps-Alerts |

## Impact
- Duration: 14 minutes
- Error rate peak: 45%
- Error budget consumed: 8% of monthly budget (approximately 17 minutes of the 216-minute budget)
- Users affected: all users hitting endpoints that required the missing configuration

## Root Cause
A missing environment variable `OTEL_EXPORTER_OTLP_ENDPOINT` caused the OpenTelemetry exporter to fail on initialisation. The application started but every request that triggered tracing threw an unhandled exception resulting in a 500 response.

## Contributing Factors
- No pre-deployment validation of required environment variables
- No staging environment to catch configuration errors before production
- Deployment pipeline did not run integration tests against the production configuration

## What Went Well
- SLO Fast Burn alert fired within 3 minutes of the incident starting
- Alert contained all required information — dashboard link, runbook link, current metric value
- Rollback took under 2 minutes once the decision was made
- Resolved alert fired automatically when the service recovered

## What Went Wrong
- No automated check for required environment variables before deployment
- First investigation step was manual log reading rather than automated diagnosis
- No automatic rollback triggered by health check failure

## Action Items

| Action | Owner | Due Date | Status |
|--------|-------|----------|--------|
| Add environment variable validation to deployment script | DevOps | 2026-05-20 | Open |
| Add integration test suite that runs against prod config | Engineering | 2026-05-25 | Open |
| Implement automatic rollback on 3 consecutive health check failures | DevOps | 2026-05-22 | Open |
| Document all required environment variables in README | DevOps | 2026-05-18 | Open |
| Add pre-deployment checklist to GitHub Actions workflow | DevOps | 2026-05-20 | Open |

## Toil Identified
1. Manual verification of environment variables before every deployment — automatable with a validation script in CI
2. Manual Slack notification to the team when an incident starts — Alertmanager now handles this automatically but escalation beyond on-call is still manual

## Lessons Learned
Configuration validation must happen in the deployment pipeline, not after the deployment. A 14-minute outage and 8% error budget consumption is an expensive way to discover a missing environment variable. The fast burn alert worked exactly as designed — the problem was in the deployment process, not the monitoring.

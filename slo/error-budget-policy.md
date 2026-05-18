# Error Budget Policy

**Service:** observability-demo
**Owner:** Engineering Lead
**Review Cadence:** Monthly
**Last Reviewed:** May 2026

---

## What is an Error Budget?

An error budget is the maximum amount of unreliability a service is allowed to have within a given time window, derived from the SLO target.

```
Error Budget = (1 − SLO target) × measurement window
```

It is a shared contract between product and engineering: as long as budget remains, engineering can ship features and accept calculated risk. When the budget is exhausted, reliability takes absolute priority over feature velocity.

---

## Current SLO Targets and Error Budgets

| SLO | Target | Window | Error Budget |
|---|---|---|---|
| Availability | 99.5% | 30 days | 216 minutes of downtime |
| Latency (< 500ms) | 95% of requests | 30 days | 5% of requests may be slow |
| Error Rate | 99% success | 30 days | 432 minutes equivalent |
| CPU Saturation | < 80% for 95% of time | 24 hours | 72 minutes above threshold |

---

## Burn Rate Thresholds

Error budget is monitored using multi-window burn rate alerts defined in `prometheus/rules/slo-burn-rate.yml`.

| Alert | Burn Rate | Window | Meaning |
|---|---|---|---|
| Fast Burn (critical) | > 14.4× | 1h + 5m | 2% of monthly budget consumed in 1 hour — act immediately |
| Slow Burn (warning) | > 5× | 6h + 30m | 5% of monthly budget will be consumed in 6 hours — investigate |

---

## Policy by Budget Consumed

### 0–25% consumed — Normal Operations

- All feature work proceeds at full velocity
- Reliability is monitored passively via dashboards
- No action required unless burn rate alerts fire

### 25–50% consumed — Reliability Review

- Reliability review added to the next sprint planning session
- Engineering lead is informed
- The team reviews recent deployments and alert history for the root cause
- Feature work continues but with extra scrutiny on risky changes

### 50–75% consumed — Reduced Velocity

- Non-critical feature deployments reduced by 20%
- One engineer is assigned to reliability work per sprint
- Daily error budget check-in during standups
- New features that touch the affected SLI are held until budget recovers

### 75–100% consumed — Feature Freeze

- No new feature deployments until budget recovers below 75%
- All engineering bandwidth directed at reliability
- Engineering lead and product owner notified
- Any deployment requires explicit sign-off from the engineering lead
- Incident review for any contributing event, even if resolved

### 100% consumed — Reliability Sprint

- Immediate full feature freeze — no new deployments except reliability fixes and hotfixes
- A formal reliability sprint begins with the sole goal of SLO recovery
- No new features may deploy until:
  1. The SLO is met for 7 consecutive days
  2. A root cause analysis is complete
  3. Action items from the analysis are assigned and tracked
- A blameless post-incident review is mandatory
- The SLO target itself is reviewed — if it was breached due to insufficient capacity rather than a failure, the target may need adjustment

---

## Decision Ownership

| Decision | Owner |
|---|---|
| Declare feature freeze | Engineering Lead |
| Approve reliability-only deployments during freeze | Engineering Lead |
| End the freeze and resume normal operations | Engineering Lead + Product Owner (joint) |
| Review and adjust SLO targets | Full engineering team, monthly |
| Respond to burn rate alerts | On-call engineer |
| Escalate to engineering lead | On-call engineer when budget < 50% |

---

## SLO Review Process

SLOs are reviewed **monthly** by the full engineering team. Each review covers:

1. **Historical budget consumption** — how much budget was used last month?
2. **Alert noise** — did any alerts fire incorrectly (false positives)?
3. **User impact** — did any SLO breaches correspond to user complaints or support tickets?
4. **Target calibration** — are the current targets too strict or too loose given team capacity?
5. **Toil tracking** — what manual work was required during incidents, and can any be automated?

Targets may be tightened when:
- The team consistently stays well under budget and wants to raise the bar
- User expectations have increased (e.g., the service has become business-critical)

Targets may be loosened when:
- The team is consistently burning through budget due to external factors outside their control
- A major architectural change is in progress that temporarily increases risk

Any change to SLO targets requires documentation of the reasoning and approval by the engineering lead.

---

## Relationship to DORA Metrics

Error budget consumption is directly connected to DORA metrics:

- High **Change Failure Rate (CFR)** → fast budget consumption → may trigger freeze
- Long **Lead Time for Changes (LTC)** → delayed reliability fixes → slower budget recovery
- Poor **MTTR** → extended SLO violations → accelerated burn
- High **Deployment Frequency** with low CFR → confidence to maintain SLO while shipping

When error budget is below 50%, DORA targets should be re-evaluated: slowing deployment frequency while improving test coverage can reduce CFR and stabilise the budget.

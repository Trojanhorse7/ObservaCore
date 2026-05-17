## Description

<!-- Describe what this PR does and why. Be specific about what changed. -->

## Related Issue

<!-- Link to the GitHub issue if one exists. Not required for infra changes. -->

## Type of Change

- [ ] New feature / new component
- [ ] Bug fix
- [ ] Config change (Prometheus, Alertmanager, Loki, Tempo, OTel)
- [ ] Dashboard update (Grafana JSON)
- [ ] Alert rule change
- [ ] CI/CD pipeline change
- [ ] Documentation update
- [ ] Refactor / cleanup

## Services Affected

<!-- Tick every service this PR touches -->

- [ ] Prometheus
- [ ] Loki
- [ ] Tempo
- [ ] Grafana
- [ ] Alertmanager
- [ ] Node Exporter
- [ ] Blackbox Exporter
- [ ] OTel Collector
- [ ] GitHub Actions

## How to Verify

<!-- Step-by-step instructions for reviewing this PR. Be specific. -->

1.
2.
3.

## Alert / Dashboard Changes

<!-- If you added or changed alert rules or dashboards, fill this in -->

- Alert rules added/changed:
- Dashboards added/changed:
- Runbook updated: Yes / No / N/A

## Rollback Plan

<!-- How do we undo this if something goes wrong after merge? -->

## Screenshots

<!-- Grafana panels, Prometheus targets, Slack alerts, terminal output — anything that shows it works -->

## Checklist

- [ ] Config files are valid (ran `promtool check rules` / `amtool check-config` where applicable)
- [ ] No hardcoded secrets, IPs, or credentials
- [ ] `localhost` used for all service URLs
- [ ] Runbook exists for any new alert rule
- [ ] Documentation updated if architecture or setup steps changed

# Runbook: Memory High

## What is this alert?
Memory usage has exceeded warning (80%) or critical (90%) threshold.

## Likely causes
- Memory leak in application code
- Too many processes running simultaneously
- Large log files held in memory
- Insufficient swap space configured

## First 3 investigation steps
1. Run `free -h` to see full memory breakdown
2. Run `ps aux --sort=-%mem | head -20` to see top memory consumers
3. Check application logs for OutOfMemory errors with `sudo journalctl -u demo-app --since "1 hour ago"`

## Resolution
- Restart the highest memory consumer: `sudo systemctl restart demo-app`
- If memory leak: roll back recent deployment
- If insufficient resources: upgrade instance type

## Should I roll back?
Roll back if memory stays above 90% after service restart.

## Escalation
Escalate immediately if OOM kills are occurring — check with `sudo dmesg | grep -i oom`.

# Runbook: SSL Certificate Expiry

**Alerts:** `SSLCertExpiryWarning` (warning), `SSLCertExpiryCritical` (critical)
**Severity:** warning / critical
**Dashboard:** http://localhost:3000/d/blackbox-exporter

---

## What is this alert?

The Blackbox Exporter probes the target endpoint and reports when the TLS certificate is approaching expiry.

- `SSLCertExpiryWarning`: certificate expires in **< 30 days** — action needed soon
- `SSLCertExpiryCritical`: certificate expires in **< 7 days** — immediate action required

When a certificate expires, all HTTPS connections will fail with a TLS error. Browsers will show a security warning and reject the connection. Automated health checks will fail, triggering `HostDown`.

---

## Likely causes

- Automated certificate renewal (Let's Encrypt / Certbot) has failed silently
- The renewal cron job is misconfigured or the certbot process is not running
- The domain's DNS is no longer pointing to this server (certificate renewal requires domain validation)
- A manually managed certificate was installed and its renewal was not tracked

---

## Investigation steps

**Step 1 — Confirm the expiry date**

```bash
# Check the certificate directly from the command line
echo | openssl s_client -connect <hostname>:443 2>/dev/null | openssl x509 -noout -dates

# Or check via Blackbox Exporter metric
curl -g 'http://localhost:9090/api/v1/query?query=probe_ssl_earliest_cert_expiry'
```

**Step 2 — Check Certbot renewal status**

```bash
# Check if certbot is installed and what certificates it manages
sudo certbot certificates

# Check renewal logs for errors
sudo journalctl -u certbot.timer --since "7 days ago"
sudo cat /var/log/letsencrypt/letsencrypt.log | tail -50
```

**Step 3 — Test renewal manually**

```bash
# Dry-run renewal to confirm it would succeed without actually renewing
sudo certbot renew --dry-run

# If the dry-run fails, check for DNS issues:
dig +short <your-domain>
```

---

## Resolution

**If Certbot is installed and the dry-run succeeds:**
```bash
sudo certbot renew --force-renewal
sudo systemctl reload nginx  # or apache2 / the service serving HTTPS
```

**If Certbot is not installed or not managing this certificate:**
```bash
sudo apt install certbot python3-certbot-nginx  # or python3-certbot-apache
sudo certbot --nginx -d <your-domain>
```

**If there is a DNS mismatch (the domain does not resolve to this server):**
- Update the DNS A record to point to this server's IP
- Wait for DNS propagation (up to 48 hours)
- Then run `sudo certbot renew --force-renewal`

**Enable automatic renewal** (if not already enabled):
```bash
# Certbot should install a systemd timer automatically
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
sudo systemctl status certbot.timer
```

---

## Rollback decision

Not applicable. Certificate renewal is additive — it replaces an expiring cert with a new one. There is no rollback, only forward renewal.

---

## Escalation

- `SSLCertExpiryWarning` (< 30 days): assign to on-call, resolve within 24 hours
- `SSLCertExpiryCritical` (< 7 days): page the on-call engineer immediately — the service will go down when it expires
- If the domain is controlled by another team or third party, escalate to them immediately

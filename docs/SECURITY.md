# SECURITY.md — Security Architecture

## Threat Model

Based on CVE-2026-25253 and the 93% auth-bypass rate across public OpenClaw instances, our primary threats are:

| Threat | Mitigation |
|--------|-----------|
| Malicious skills (ClawHub) | Whitelist-only skill install — ClawHub blocked by default |
| API key theft via malicious webpage (CVE-2026-25253) | Keys encrypted at rest in vault; never in plaintext env vars |
| Prompt injection via group chats | groupPolicy="allowlist" enforced in template config |
| Unauthorized API access | Auth token required; Nginx rate limiting |
| SSH brute force | fail2ban (3 strikes = 24h ban); key-only auth |
| Privilege escalation | auditd monitors setuid/setgid; root commands logged |
| Data exfiltration (Basic) | Outbound allow-all with logging |
| Data exfiltration (Pro/Enterprise) | Egress filtering — only DNS/HTTP/HTTPS/NTP/SMTP outbound |
| File tampering | AIDE integrity monitoring (Enterprise: daily checks) |
| Rootkits | rkhunter weekly scans (Pro+) |
| Cross-instance contamination | Each VM is fully isolated; unique machine-id, SSH keys, vault key |
| Stale CVEs | Daily auto-update timer for OpenClaw; OS unattended-upgrades |

## CIA Triad Implementation

### Confidentiality
- **Network isolation:** Each customer gets their own VM — no shared infrastructure
- **Encrypted secrets vault:** API keys stored with AES-256-CBC, key derived from unique machine-id
- **No shared credentials:** Vault key is machine-unique; compromising one instance doesn't expose others
- **Egress filtering (Pro+):** Limits what data can leave the instance

### Integrity
- **Skill whitelist:** No raw ClawHub access — only Right Servers-vetted skills
- **Audit logging:** Every command executed by root is captured in auditd
- **File integrity monitoring:** AIDE baseline on first boot; daily checks on Enterprise
- **Action logging:** OpenClaw agent actions logged to `/var/log/openclaw-actions/`

### Availability
- **Automated backups:** Daily backup of workspace + config, 7-day retention
- **Auto-updates:** Daily OpenClaw updates, OS unattended-upgrades
- **Health monitoring:** All critical services managed by systemd with auto-restart
- **Nginx proxy:** Handles TLS termination, protects OpenClaw gateway directly

## Skill Vetting Process

Before adding a skill to `approved-skills.txt`:

1. **Review SKILL.md** — check what tools/permissions it requests
2. **Review source code** — inspect any scripts for outbound calls, file access
3. **Test in isolated environment** — deploy to a test instance, observe behavior
4. **Check for update history** — is the skill maintained? Recent commits?
5. **Add to whitelist** — update `approved-skills.txt` and commit to RightClaw-Build

## CVE Response SLA

| Severity | Response Time |
|----------|--------------|
| Critical (CVSS 9+) | Patch within 24 hours |
| High (CVSS 7-8.9) | Patch within 72 hours |
| Medium (CVSS 4-6.9) | Patch within 14 days |
| Low | Next scheduled maintenance |

Auto-update timer handles most OpenClaw CVEs automatically.
OS CVEs handled via `unattended-upgrades` (already enabled on Ubuntu 22.04).

## Audit Log Locations

| Log | Location |
|-----|----------|
| auditd (root commands) | `/var/log/audit/audit.log` |
| OpenClaw actions | `/var/log/openclaw-actions/` |
| fail2ban bans | `/var/log/fail2ban.log` |
| Nginx access | `/var/log/nginx/access.log` |
| First-boot log | `/var/log/rightservers-firstboot.log` |
| Backup log | `/var/log/rightservers-backup.log` |
| Compliance reports (Enterprise) | `/var/log/rightservers-compliance/` |

## What Customers Get (Audit Access)

Customers can request logs via support ticket. On Enterprise tier, weekly compliance reports are generated automatically and can be emailed or made available via SFTP.

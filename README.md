# RightClaw-Build

**Right Servers — Secure OpenClaw VPS Product**

This repo contains everything needed to build, maintain, and deploy the Right Servers OpenClaw VPS offering: VM template scripts, tier upgrade configs, WHMCS integration hooks, and documentation.

---

## Product Overview

A fully managed, security-hardened OpenClaw VPS built for businesses that need AI automation but can't afford to evaluate or secure it themselves.

**Target market:** CPAs, law firms, real estate brokers, medical practices, SMBs — managed by MSPs and vCIOs.

**Differentiator:** Security-first. Every instance is isolated, audited, and maintained. Not another 5-minute wrapper.

---

## Tiers

| Feature | Basic | Pro | Enterprise |
|---------|-------|-----|------------|
| Isolated VPS | ✅ | ✅ | ✅ |
| OS hardening + fail2ban | ✅ | ✅ | ✅ |
| UFW firewall | ✅ | ✅ | ✅ |
| Skill whitelist (no raw ClawHub) | ✅ | ✅ | ✅ |
| Encrypted secrets vault | ✅ | ✅ | ✅ |
| Automated backups (7-day) | ✅ | ✅ | ✅ |
| Auto-updates + CVE patching | ✅ | ✅ | ✅ |
| Nginx reverse proxy + TLS | ✅ | ✅ | ✅ |
| Egress filtering | ❌ | ✅ | ✅ |
| Enhanced action audit logging | ❌ | ✅ | ✅ |
| Intrusion detection (rkhunter) | ❌ | ✅ | ✅ |
| Compliance reports (weekly) | ❌ | ❌ | ✅ |
| Docker isolation per agent | ❌ | ❌ | ✅ |
| AIDE file integrity (daily) | ❌ | ❌ | ✅ |
| Immutable audit trail | ❌ | ❌ | ✅ |

---

## Repository Structure

```
RightClaw-Build/
├── README.md                        # This file
├── vm-template/                     # Template VM configuration
│   ├── scripts/
│   │   ├── first-boot.sh            # Runs once on each AutoVM clone
│   │   ├── backup.sh                # Daily backup cron script
│   │   ├── upgrade-pro.sh           # Activates Pro tier features
│   │   ├── upgrade-enterprise.sh    # Activates Enterprise tier features
│   │   ├── template-prep.sh         # Run before snapshotting in vCenter
│   │   └── vault.sh                 # Encrypted secrets vault
│   ├── approved-skills.txt          # Skill whitelist
│   ├── audit-rules.conf             # auditd rules
│   ├── fail2ban-jail.local          # fail2ban config
│   ├── nginx-openclaw.conf          # Nginx reverse proxy
│   ├── rightservers-firstboot.service # systemd first-boot unit
│   └── sshd_config                  # Hardened SSH config
├── docs/
│   ├── BUILD.md                     # How to build and update the template
│   ├── AUTOVM.md                    # AutoVM integration notes
│   ├── SECURITY.md                  # Security architecture
│   └── PROVISIONING.md             # Customer provisioning workflow
├── whmcs-hooks/                     # WHMCS PHP hook files
└── tier-configs/                    # Per-tier configuration overlays
```

---

## Template Build Steps

See [docs/BUILD.md](docs/BUILD.md) for the full build guide.

**Quick summary:**
1. Spin up Ubuntu 22.04 LTS VM (min 2 vCPU / 4GB RAM) on vCenter
2. Run the build process (documented in BUILD.md)
3. When complete: `ssh root@<ip> /opt/rightservers/scripts/template-prep.sh`
4. Power off, convert to template in vCenter
5. Configure AutoVM to clone from this template

---

## AutoVM Integration

- open-vm-tools pre-installed and running
- `rightservers-firstboot.service` enabled — triggers on first boot after clone
- First boot: regenerates SSH host keys, machine-id, sets hostname, builds AIDE baseline
- See [docs/AUTOVM.md](docs/AUTOVM.md)

---

## Current Template VM

- **Address:** 170.205.18.168 (build VM — not yet converted to template)
- **OS:** Ubuntu 22.04.1 LTS
- **OpenClaw:** 2026.2.25
- **Node:** v22.22.0
- **Status:** Build in progress

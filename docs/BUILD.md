# BUILD.md — Template Build Guide

How to build or rebuild the Right Servers OpenClaw VPS template from scratch.

## Requirements

- Ubuntu 22.04 LTS VM on vCenter (min 2 vCPU / 4GB RAM / 16GB disk)
- open-vm-tools should be pre-installed (it is in Ubuntu 22.04)
- Internet access from the VM (for package installs)
- SSH access as root

## Build Process

### Stage 1 — OS Hardening & Dependencies

```bash
apt-get update && apt-get upgrade -y
apt-get install -y curl wget git unzip jq ufw fail2ban nginx certbot \
  python3-certbot-nginx auditd aide ca-certificates gnupg docker.io \
  docker-compose cron logrotate rkhunter chkrootkit
```

Node.js 22:
```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
```

### Stage 2 — SSH Hardening

- PasswordAuthentication disabled (key-only)
- MaxAuthTries 4
- LoginGraceTime 30
- Root login via key only (`prohibit-password`)
- Login banner configured
- Config at: `vm-template/sshd_config`

### Stage 3 — Firewall (UFW)

Inbound: deny all except SSH (22), HTTP (80), HTTPS (443), OpenClaw Gateway (18789)
Outbound: allow all (Basic/Pro egress filtering locks this down further)

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 18789/tcp
ufw enable
```

### Stage 4 — fail2ban

- SSH: 3 failures = 24h ban
- Config at: `vm-template/fail2ban-jail.local`

### Stage 5 — Audit Rules

- All root commands logged
- OpenClaw workspace monitored (read/write/exec)
- SSH config, passwd, sudoers, cron monitored
- Config at: `vm-template/audit-rules.conf`

### Stage 6 — OpenClaw Install

```bash
npm install -g openclaw
```

### Stage 7 — Encrypted Vault

Machine-unique AES-256-CBC encrypted secrets store.
Script at: `vm-template/scripts/vault.sh`
Vault file: `/opt/openclaw-secure/.vault` (chmod 600)

Key derivation: `sha256(machine-id + "openclaw")` — unique per clone since first-boot regenerates machine-id.

### Stage 8 — Skill Whitelist

ClawHub access blocked. Only approved skills can be installed.
Whitelist at: `vm-template/approved-skills.txt`
Guard script: `/usr/local/bin/openclaw-install-skill`

### Stage 9 — Auto-Updates

Daily systemd timer: `npm install -g openclaw@latest`
Randomized delay up to 1h to avoid thundering herd on fleet updates.

### Stage 10 — Nginx Reverse Proxy

Proxies port 80/443 → OpenClaw Gateway (18789)
WebSocket support enabled for real-time agent communication.
Config at: `vm-template/nginx-openclaw.conf`

### Stage 11 — Scripts Deployment

All scripts deployed to `/opt/rightservers/scripts/`:
- `first-boot.sh` — systemd oneshot, runs once on first boot after clone
- `backup.sh` — daily cron at 03:00
- `upgrade-pro.sh` — run to activate Pro tier
- `upgrade-enterprise.sh` — run to activate Enterprise tier
- `template-prep.sh` — run before converting to vCenter template

## Converting to Template

```bash
ssh root@<build-vm-ip>
/opt/rightservers/scripts/template-prep.sh
# Wait for it to complete
poweroff
```

Then in vCenter: right-click VM → Convert to Template.

## Updating the Template

To update an existing template (e.g. new OpenClaw version):
1. Deploy a clone from the template
2. Make changes
3. Run `template-prep.sh` again
4. Power off
5. Convert to new template version (keep old one until tested)

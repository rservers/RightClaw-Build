# FLEET.md — Fleet Update System

## How It Works

Every deployed VM pulls updates automatically from GitHub on a daily schedule.
You can also push updates immediately to all VMs (or a specific tier) from the management VM.

```
GitHub (rservers/RightClaw-Build)
    └── VERSION file ← you bump this when releasing an update
    └── vm-template/scripts/ ← updated scripts
    └── vm-template/approved-skills.txt ← updated skill whitelist

        ↓ (pulled daily by each VM)       ↓ (pushed immediately by you)

Each deployed VM                    Fleet Manager (this OpenClaw VM)
  /opt/rightservers/scripts/          ~/fleet/fleet-manager.sh
  update.sh (runs via cron)           → SSH to all VMs → trigger update.sh
```

## Fleet Manager — Commands

All commands run from the OpenClaw management VM.

### See all deployed VMs
```bash
~/fleet/fleet-manager.sh list
```
Output:
```
  IP               | Tier       | Service ID | Product
  ─────────────────┼────────────┼────────────┼────────────────────
  170.205.18.100   │ BASIC      │ 1234       │ OpenClaw VPS Basic
  170.205.18.101   │ PRO        │ 1235       │ OpenClaw VPS Pro
```

### Check status of all VMs
```bash
~/fleet/fleet-manager.sh status
```
Shows: hostname, version, tier, uptime for every active VM.

### Push an update to all VMs RIGHT NOW
```bash
~/fleet/fleet-manager.sh update
```

### Push update to Pro and Enterprise only
```bash
~/fleet/fleet-manager.sh update --tier PRO
```

### Run any command across the whole fleet
```bash
~/fleet/fleet-manager.sh run "openclaw --version"
~/fleet/fleet-manager.sh run "systemctl status fail2ban | grep Active"
~/fleet/fleet-manager.sh run "df -h /" --tier ENTERPRISE
```

### Target a single VM
```bash
~/fleet/fleet-manager.sh vm 170.205.18.100 "openclaw gateway restart"
```

---

## Releasing an Update

### The normal workflow

1. **Make your changes** to scripts/skills in `RightClaw-Build` or `Rightclaw-Skills`
2. **Publish the release** — bumps VERSION and pushes to GitHub:
   ```bash
   ~/fleet/fleet-manager.sh publish 1.1.0 "Added WHMCS skill, updated audit rules"
   ```
3. **VMs auto-update** overnight (randomized between 2-5 AM to avoid thundering herd)
4. **Or push immediately:**
   ```bash
   ~/fleet/fleet-manager.sh update
   ```

### What gets updated on each VM
- Scripts in `/opt/rightservers/scripts/` (pulled from GitHub)
- Skill whitelist (`approved-skills.txt`)
- All installed skills (pulled from `Rightclaw-Skills` repo)
- OpenClaw itself (`npm install -g openclaw@latest`)

### Force a reboot after update
In `VERSION`, set `"force_reboot": true`. VMs will reboot 60s after updating.
**Reset it back to false** after releasing, or every daily run will reboot VMs.

### Tier-targeted updates
In `VERSION`, set `"min_tier": "PRO"` to only update Pro and Enterprise instances.
Use `"min_tier": "BASIC"` (default) to update everyone.

---

## What Happens on Each VM (Daily Cron)

```
~3 AM (randomized) → update.sh runs
  1. Fetch VERSION from GitHub
  2. Compare to /opt/rightservers/version
  3. If same version → only check npm update, exit
  4. If new version:
     a. Download updated scripts from GitHub
     b. Update skill whitelist
     c. Update all installed skills
     d. npm install -g openclaw@latest
     e. Restart OpenClaw gateway
     f. Save new version to /opt/rightservers/version
     g. Reboot if manifest says force_reboot=true
```

## Update Logs

On each VM:
```bash
tail -f /var/log/rightservers-update.log
```

On the management VM:
```bash
tail -f /var/log/rightservers-fleet.log
```

## Fleet SSH Key

The fleet manager uses a dedicated ed25519 key (`~/.ssh/rightservers_fleet`) that is:
- Baked into `first-boot.sh` — injected automatically on every new VM deploy
- **Never removed** by `template-prep.sh` (it's in first-boot, not the template)
- Separate from personal keys — rotate without affecting customers

To rotate the fleet key:
1. Generate a new key: `ssh-keygen -t ed25519 -f ~/.ssh/rightservers_fleet_new`
2. Update the public key in `first-boot.sh`
3. Push to GitHub
4. Run: `~/fleet/fleet-manager.sh run "echo 'NEW_PUBLIC_KEY' >> /root/.ssh/authorized_keys"`
5. Swap the private key file
6. Remove the old key: `~/fleet/fleet-manager.sh run "sed -i '/old-key-comment/d' /root/.ssh/authorized_keys"`

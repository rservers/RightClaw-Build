# PROVISIONING.md — How to Use This System

A complete walkthrough of setting up and running the Right Servers OpenClaw VPS product.

---

## Overview: What Happens When a Customer Orders

```
Customer clicks Buy
       ↓
WHMCS creates the order
       ↓
You accept the order (or auto-accept)
       ↓
AutoVM clones the template VM
  → Injects: hostname, IP, root password
       ↓
VM boots → first-boot.sh runs automatically
  → Regenerates SSH keys & machine-id
  → Sets hostname
  → Builds AIDE baseline
  → Configures backup cron
       ↓
WHMCS fires AfterModuleCreate
  → rightservers_openclaw.php hook kicks in
  → Waits 60s for VM to finish booting
  → SSHes into the VM
  → Runs upgrade-pro.sh or upgrade-enterprise.sh (if Pro/Enterprise)
       ↓
Customer gets welcome email with:
  → IP address
  → Root password (or OpenClaw dashboard URL)
  → Getting started instructions
```

---

## One-Time Setup (Do This Once)

### Step 1 — Build and convert the template

```bash
# Template is already built at 170.205.18.168
# When ready to convert:
ssh root@170.205.18.168
/opt/rightservers/scripts/template-prep.sh
poweroff
```
Then in vCenter: right-click the VM → **Convert to Template**.
Name it something like `rightservers-openclaw-base-v1`.

### Step 2 — Configure AutoVM

In your AutoVM admin panel:
- Point your OpenClaw VPS products at the template you just created
- AutoVM handles: cloning, IP assignment, hostname injection, password injection
- Refer to AutoVM docs for your specific version's template configuration

### Step 3 — Create WHMCS products

In WHMCS admin → **Setup → Products/Services**:

Create a product group: **"OpenClaw VPS"**

Create 3 products inside it:

| Product Name | Module | Notes |
|---|---|---|
| OpenClaw VPS Basic | AutoVM module | Base tier — no upgrade script |
| OpenClaw VPS Pro | AutoVM module | Runs upgrade-pro.sh after deploy |
| OpenClaw VPS Enterprise | AutoVM module | Runs upgrade-enterprise.sh after deploy |

For each product, set the pricing, description, and point it at the AutoVM server.

### Step 4 — Install the WHMCS hook

Upload `whmcs-hooks/rightservers_openclaw.php` to your WHMCS server:

```bash
scp whmcs-hooks/rightservers_openclaw.php \
  root@cpanel11.rightservers.com:/home/portal/public_html/includes/hooks/
```

That's it. WHMCS auto-loads all files in `includes/hooks/`.

### Step 5 — Verify the hook loaded

In WHMCS admin: **Utilities → Logs → Activity Log**
Place a test order and look for entries starting with `RightServers OpenClaw`.

---

## Day-to-Day Operations

### Checking a customer's instance

```bash
ssh root@<customer-ip>
openclaw status
cat /opt/rightservers/tier       # shows BASIC / PRO / ENTERPRISE
cat /var/log/rightservers-firstboot.log  # first-boot audit trail
```

### Upgrading a customer from Basic → Pro

```bash
ssh root@<customer-ip>
/opt/rightservers/scripts/upgrade-pro.sh
```

Then update their product in WHMCS to the Pro product.

### Upgrading a customer from Pro → Enterprise

```bash
ssh root@<customer-ip>
/opt/rightservers/scripts/upgrade-enterprise.sh
```

### Checking backups

```bash
ssh root@<customer-ip>
ls -lh /var/backups/openclaw/
```

Backups run daily at 03:00. Files kept for 7 days.

### Checking audit logs

```bash
# See all OpenClaw-related audit events
ssh root@<customer-ip>
ausearch -k openclaw | tail -50

# See all root commands run today
ausearch -k root_commands -ts today
```

---

## Updating the Template

When OpenClaw releases a new version or you want to add features:

1. Deploy a new VM from the existing template (use AutoVM or vCenter)
2. SSH in and make your changes
3. Run `template-prep.sh` again
4. Power off → Convert to new template (e.g. `rightservers-openclaw-base-v2`)
5. Update AutoVM to use the new template
6. Keep the old template until you've tested a few new deploys

---

## Troubleshooting

### Hook not firing?
- Check WHMCS Activity Log for errors
- Confirm file is in `/home/portal/public_html/includes/hooks/`
- Check PHP errors: `tail -f /home/portal/public_html/error_log`

### VM not reachable after 60s?
- Increase `RS_BOOT_WAIT` in the hook config (line 52)
- Check if AutoVM injects IP correctly — WHMCS needs the IP in the service record

### Tier script failed?
- SSH into the VM manually and run the script yourself
- Check `/var/log/rightservers-firstboot.log` for first-boot status

### Customer locked out of SSH?
- fail2ban may have banned their IP
- `ssh root@<customer-ip> fail2ban-client status sshd`
- `ssh root@<customer-ip> fail2ban-client set sshd unbanip <their-ip>`

---

## File Locations Quick Reference

| What | Where |
|------|-------|
| Hook file (WHMCS) | `/home/portal/public_html/includes/hooks/rightservers_openclaw.php` |
| Tier scripts (VM) | `/opt/rightservers/scripts/` |
| Encrypted vault (VM) | `/opt/openclaw-secure/.vault` |
| Skill whitelist (VM) | `/opt/openclaw-skills-whitelist/approved-skills.txt` |
| Backups (VM) | `/var/backups/openclaw/` |
| Audit logs (VM) | `/var/log/audit/audit.log` |
| First-boot log (VM) | `/var/log/rightservers-firstboot.log` |
| OpenClaw config (VM) | `/root/.openclaw/` |

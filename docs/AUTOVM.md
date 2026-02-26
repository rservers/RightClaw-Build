# AUTOVM.md — AutoVM Integration

## Requirements Met

| AutoVM Requirement | Status |
|---|---|
| VMware Tools installed | ✅ open-vm-tools active |
| vCenter guest customization support | ✅ |
| Clean shutdown state before template conversion | ✅ template-prep.sh handles this |
| Unique SSH host keys per clone | ✅ first-boot.sh regenerates them |
| Unique machine-id per clone | ✅ first-boot.sh regenerates it |

## How Provisioning Works

1. Customer orders via WHMCS
2. AutoVM clones the template, injects: hostname, IP, root password via guest customization
3. VM boots → `rightservers-firstboot.service` triggers automatically
4. First boot script runs:
   - Regenerates SSH host keys
   - Regenerates machine-id (ensures vault key is unique)
   - Sets hostname from AutoVM injection
   - Initializes OpenClaw workspace
   - Builds AIDE file integrity baseline
   - Configures backup cron
   - Disables itself (won't run again)
5. Instance is ready

## Tier Activation

After AutoVM deploys, WHMCS hook calls the appropriate upgrade script:

- **Basic:** No additional steps — template ships at Basic tier
- **Pro:** `ssh root@<ip> /opt/rightservers/scripts/upgrade-pro.sh`
- **Enterprise:** `ssh root@<ip> /opt/rightservers/scripts/upgrade-enterprise.sh`

## Credentials Delivered to Customer

AutoVM injects the root password. OpenClaw dashboard is available at:
`http://<instance-ip>` (proxied via Nginx → port 18789)

For production, point a DNS record at the instance IP and run:
```bash
certbot --nginx -d customer.rightservers.com
```

## WHMCS Provisioning Hook

See `whmcs-hooks/` for the PHP module that triggers tier upgrades automatically on order acceptance.

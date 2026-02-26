#!/bin/bash
# Right Servers OpenClaw VPS - First Boot Provisioning
# AutoVM injects: hostname, IP, root password via guest customization
# This script completes the OpenClaw-specific setup on first boot

LOGFILE="/var/log/rightservers-firstboot.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "[First Boot] Starting at $(date)"

# --- 1. Regenerate SSH host keys (each VM must be unique) ---
echo '[First Boot] Regenerating SSH host keys...'
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A
systemctl restart sshd
echo 'SSH host keys regenerated'

# --- 2. Regenerate machine-id (critical for vault key uniqueness) ---
echo '[First Boot] Regenerating machine-id...'
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup
cp /etc/machine-id /var/lib/dbus/machine-id
echo "New machine-id: $(cat /etc/machine-id)"

# --- 3. Set hostname from AutoVM injection ---
NEW_HOSTNAME=$(hostname)
echo "[First Boot] Hostname: $NEW_HOSTNAME"
hostnamectl set-hostname "$NEW_HOSTNAME"
sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts

# --- 4. Initialize OpenClaw workspace for this instance ---
echo '[First Boot] Setting up OpenClaw workspace...'
mkdir -p /root/.openclaw/workspace/memory
openclaw gateway start || true
sleep 3

# --- 5. Initialize AIDE file integrity baseline ---
echo '[First Boot] Building AIDE integrity baseline (this takes a minute)...'
aideinit --yes --force 2>/dev/null || aide --init 2>/dev/null || true
if [ -f /var/lib/aide/aide.db.new ]; then
  cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  echo 'AIDE baseline established'
fi

# --- 6. Configure automated backups ---
echo '[First Boot] Configuring backups...'
INSTANCE_ID=$(cat /etc/machine-id | head -c 12)
cat > /etc/cron.d/rightservers-backup << BACKUPCRON
# Right Servers OpenClaw - Automated Backup
# Daily backup of OpenClaw workspace and config
0 3 * * * root /opt/rightservers/scripts/backup.sh >> /var/log/rightservers-backup.log 2>&1
BACKUPCRON

# --- 7. Send provisioning complete notification ---
echo '[First Boot] Provisioning complete!'
echo "Instance: $NEW_HOSTNAME | Machine-ID: $(cat /etc/machine-id) | Date: $(date)" >> /var/log/rightservers-firstboot.log

# --- 8. Disable this script from running again ---
systemctl disable rightservers-firstboot.service 2>/dev/null || true
rm -f /etc/systemd/system/rightservers-firstboot.service

echo "[First Boot] Done at $(date)"

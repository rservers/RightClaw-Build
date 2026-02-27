#!/bin/bash
# Fix AutoVM compatibility on the template VM
# Run this on the cloned template before re-running template-prep.sh

echo "[Fix] Setting root password to AutoVM default..."
echo 'root:123QWEqwe' | chpasswd

echo "[Fix] Enabling password auth for AutoVM SSH access..."
cat > /etc/ssh/sshd_config << 'SSHEOF'
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
LoginGraceTime 30
PermitRootLogin yes
StrictModes yes
MaxAuthTries 4
MaxSessions 5
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
AllowUsers root
ClientAliveInterval 300
ClientAliveCountMax 2
Banner /etc/ssh/banner
SSHEOF
systemctl reload sshd
echo "[Fix] SSH config updated — password auth ON for AutoVM"

echo "[Fix] Updating first-boot.sh to harden SSH AFTER AutoVM setup..."
# first-boot.sh already handles this — it disables password auth
# and injects the fleet key after AutoVM's script has run.
# The key is ordering: AutoVM script runs on first boot, then
# our systemd first-boot service runs on the same boot (After=network.target)

# Update first-boot.sh to disable password auth post-AutoVM
cat >> /opt/rightservers/scripts/first-boot.sh << 'FBEOF'

# --- SECURITY HARDENING (runs after AutoVM has set hostname/IP/password) ---
echo '[First Boot] Disabling SSH password auth post-AutoVM setup...'
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload sshd
echo 'SSH password auth disabled'
FBEOF

echo "[Fix] All done. Now run: /opt/rightservers/scripts/template-prep.sh"

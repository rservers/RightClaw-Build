#!/bin/bash
# Right Servers OpenClaw VPS - Template Preparation Script
# Run this ONCE just before converting the VM to a template in vCenter/AutoVM
# DO NOT run on live customer instances!

echo '================================================'
echo ' Right Servers - Template Prep'
echo ' This will clean the VM for cloning.'
echo ' Press CTRL+C within 10 seconds to abort.'
echo '================================================'
sleep 10

echo '[Prep] Stopping services...'
systemctl stop openclaw-gateway 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true

echo '[Prep] Clearing SSH host keys (regenerated on first boot)...'
rm -f /etc/ssh/ssh_host_*

echo '[Prep] Clearing SSH authorized keys...'
rm -f /root/.ssh/authorized_keys

echo '[Prep] Clearing machine-id (regenerated on first boot)...'
> /etc/machine-id
> /var/lib/dbus/machine-id 2>/dev/null || true

echo '[Prep] Clearing logs...'
find /var/log -type f -name '*.log' -exec truncate -s 0 {} \;
find /var/log -type f -name 'syslog' -exec truncate -s 0 {} \;
find /var/log -type f -name 'auth.log' -exec truncate -s 0 {} \;
journalctl --rotate --vacuum-time=1s 2>/dev/null || true

echo '[Prep] Clearing shell history...'
history -c
> /root/.bash_history
find /home -name '.bash_history' -exec truncate -s 0 {} \;

echo '[Prep] Clearing apt cache...'
apt-get clean -q

echo '[Prep] Clearing temp files...'
rm -rf /tmp/* /var/tmp/*

echo '[Prep] Clearing OpenClaw sessions (keep config, clear state)...'
rm -rf /root/.openclaw/agents/*/sessions/*.json 2>/dev/null || true

echo '[Prep] Ensuring first-boot service is enabled...'
systemctl enable rightservers-firstboot.service

echo ''
echo '================================================'
echo ' Template prep complete.'
echo ' The VM is ready to be shut down and converted'
echo ' to a template in vCenter / AutoVM.'
echo ''
echo ' Shut down now with: poweroff'
echo '================================================'

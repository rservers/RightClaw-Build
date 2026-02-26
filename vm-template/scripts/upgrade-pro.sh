#!/bin/bash
# Right Servers OpenClaw VPS - Upgrade to PRO tier
echo '[PRO Upgrade] Starting...'

# 1. Egress filtering - whitelist only necessary outbound
echo '[PRO] Configuring egress filtering...'
ufw default deny outgoing
# Allow DNS
ufw allow out 53/udp
ufw allow out 53/tcp
# Allow HTTPS (APIs, OpenClaw, npm updates)
ufw allow out 443/tcp
# Allow HTTP (package updates)
ufw allow out 80/tcp
# Allow NTP
ufw allow out 123/udp
# Allow SMTP outbound (notifications)
ufw allow out 587/tcp
ufw allow out 465/tcp
echo 'Egress filtering enabled (deny all except DNS/HTTP/HTTPS/NTP/SMTP)'

# 2. Enhanced audit logging - OpenClaw action log
echo '[PRO] Enabling enhanced action logging...'
cat > /etc/audit/rules.d/openclaw-pro.rules << 'AUDITRULES'
# PRO: Log all file writes in OpenClaw workspace
-w /root/.openclaw -p rwxa -k openclaw_all
# Log outbound connections
-a always,exit -F arch=b64 -S connect -k outbound_connections
# Log privilege escalation attempts
-a always,exit -F arch=b64 -S setuid -S setgid -k privilege_escalation
AUDITRULES
service auditd restart

# 3. OpenClaw action log - capture every command the agent runs
mkdir -p /var/log/openclaw-actions
cat > /etc/logrotate.d/openclaw-actions << 'LOGROTATE'
/var/log/openclaw-actions/*.log {
    daily
    rotate 30
    compress
    missingok
    notifempty
    create 640 root root
}
LOGROTATE

# 4. Intrusion detection - rkhunter weekly scan
cat > /etc/cron.d/rkhunter-scan << 'RKHUNTERCRON'
0 4 * * 0 root /usr/bin/rkhunter --check --skip-keypress --report-warnings-only 2>&1 | mail -s "RKHunter Report: $(hostname)" root
RKHUNTERCRON

# 5. Mark tier
echo 'PRO' > /opt/rightservers/tier
echo '[PRO Upgrade] Complete.'

#!/bin/bash
# Right Servers OpenClaw VPS - Upgrade to ENTERPRISE tier
echo '[ENTERPRISE Upgrade] Starting...'

# Run PRO first if not already done
if [ "$(cat /opt/rightservers/tier 2>/dev/null)" != 'PRO' ]; then
  /opt/rightservers/scripts/upgrade-pro.sh
fi

# 1. Compliance logging - immutable audit trail
echo '[ENTERPRISE] Setting up compliance log...'
mkdir -p /var/log/rightservers-compliance
chmod 700 /var/log/rightservers-compliance

# Make audit logs append-only
chattr +a /var/log/rightservers-compliance 2>/dev/null || true

cat > /etc/cron.d/compliance-report << 'COMPLYCRON'
# Weekly compliance report
0 6 * * 1 root /opt/rightservers/scripts/compliance-report.sh >> /var/log/rightservers-compliance/weekly.log 2>&1
COMPLYCRON

# 2. Compliance report generator
cat > /opt/rightservers/scripts/compliance-report.sh << 'COMPLIANCEOF'
#!/bin/bash
echo '=== RIGHT SERVERS COMPLIANCE REPORT ==='
echo "Generated: $(date)"
echo "Hostname: $(hostname)"
echo "Machine-ID: $(cat /etc/machine-id)"
echo ''
echo '--- Failed Login Attempts (last 7 days) ---'
journalctl -u sshd --since '7 days ago' | grep -c 'Failed' || echo '0'
echo ''
echo '--- OpenClaw Actions (last 7 days) ---'
ausearch -k openclaw -ts week 2>/dev/null | grep -c 'type=SYSCALL' || echo '0 events'
echo ''
echo '--- Firewall Blocks (last 24h) ---'
journalctl -k --since '24 hours ago' | grep -c 'UFW BLOCK' || echo '0'
echo ''
echo '--- Services Status ---'
systemctl is-active openclaw-gateway fail2ban auditd nginx docker 2>/dev/null
echo '=== END REPORT ==='
COMPLIANCEOF
chmod 755 /opt/rightservers/scripts/compliance-report.sh

# 3. Docker isolation per-agent
echo '[ENTERPRISE] Configuring Docker network isolation...'
docker network create --driver bridge --opt com.docker.network.bridge.name=openclaw-isolated openclaw-net 2>/dev/null || true

# 4. AIDE daily integrity checks
cat > /etc/cron.d/aide-daily << 'AIDECRON'
0 2 * * * root /usr/bin/aide --check 2>&1 | grep -E 'changed|added|removed' | mail -s "AIDE Integrity: $(hostname)" root || true
AIDECRON

# 5. Mark tier
echo 'ENTERPRISE' > /opt/rightservers/tier

echo '[ENTERPRISE Upgrade] Complete.'

#!/bin/bash
BACKUP_DIR="/var/backups/openclaw"
DATE=$(date +%Y-%m-%d)
mkdir -p "$BACKUP_DIR"

# Backup OpenClaw workspace and config
tar czf "$BACKUP_DIR/openclaw-workspace-${DATE}.tar.gz"   /root/.openclaw/workspace   /opt/openclaw-secure   /opt/rightservers   2>/dev/null

# Keep last 7 days only
find "$BACKUP_DIR" -name '*.tar.gz' -mtime +7 -delete

echo "$(date): Backup complete -> $BACKUP_DIR/openclaw-workspace-${DATE}.tar.gz"
ls -lh "$BACKUP_DIR/"

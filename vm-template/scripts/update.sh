#!/bin/bash
# Right Servers OpenClaw VPS — Auto-Update Agent
# Runs on each deployed VM. Checks GitHub for updates and applies them.
# Scheduled via cron to run daily. Can also be triggered remotely by fleet manager.
#
# Update sources:
#   - RightClaw-Build (scripts, config)  → github.com/rservers/RightClaw-Build
#   - Rightclaw-Skills (skills)          → github.com/rservers/Rightclaw-Skills
#   - OpenClaw itself                    → npm latest

LOGFILE="/var/log/rightservers-update.log"
LOCKFILE="/var/run/rightservers-update.lock"
STATE_FILE="/opt/rightservers/update-state.json"
BUILD_REPO="https://raw.githubusercontent.com/rservers/RightClaw-Build/main"
SKILLS_REPO="https://raw.githubusercontent.com/rservers/Rightclaw-Skills/main"
TIER=$(cat /opt/rightservers/tier 2>/dev/null || echo "BASIC")
CURRENT_VERSION=$(cat /opt/rightservers/version 2>/dev/null || echo "0.0.0")

exec >> "$LOGFILE" 2>&1
echo ""
echo "=== Update Check: $(date) | Tier: $TIER | Version: $CURRENT_VERSION ==="

# Prevent concurrent runs
if [ -f "$LOCKFILE" ]; then
    echo "[update] Already running (lock exists). Exiting."
    exit 0
fi
touch "$LOCKFILE"
trap "rm -f $LOCKFILE" EXIT

# -------------------------------------------------------
# 1. Fetch VERSION manifest from GitHub
# -------------------------------------------------------
echo "[update] Fetching version manifest..."
MANIFEST=$(curl -sf "$BUILD_REPO/VERSION" 2>/dev/null)
if [ -z "$MANIFEST" ]; then
    echo "[update] Could not fetch manifest. Skipping."
    exit 1
fi

LATEST_VERSION=$(echo "$MANIFEST" | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])")
FORCE_REBOOT=$(echo "$MANIFEST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('force_reboot', False))")
CHANGELOG=$(echo "$MANIFEST" | python3 -c "import sys,json; print(json.load(sys.stdin)['changelog'])")
MIN_TIER=$(echo "$MANIFEST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('min_tier', 'BASIC'))")

echo "[update] Latest: $LATEST_VERSION | Current: $CURRENT_VERSION"

# Tier check
tier_rank() {
    case "$1" in
        BASIC)      echo 1 ;;
        PRO)        echo 2 ;;
        ENTERPRISE) echo 3 ;;
        *)          echo 0 ;;
    esac
}
if [ "$(tier_rank $TIER)" -lt "$(tier_rank $MIN_TIER)" ]; then
    echo "[update] Update requires tier $MIN_TIER — this instance is $TIER. Skipping."
    exit 0
fi

# Check if update needed
if [ "$LATEST_VERSION" = "$CURRENT_VERSION" ]; then
    echo "[update] Already up to date ($CURRENT_VERSION). Nothing to do."
    # Still check OpenClaw npm update
    update_openclaw
    exit 0
fi

echo "[update] Update available: $CURRENT_VERSION → $LATEST_VERSION"
echo "[update] Changelog: $CHANGELOG"

# -------------------------------------------------------
# 2. Update scripts from RightClaw-Build
# -------------------------------------------------------
echo "[update] Updating scripts..."
SCRIPTS_DIR="/opt/rightservers/scripts"
for script in update.sh backup.sh upgrade-pro.sh upgrade-enterprise.sh; do
    NEW=$(curl -sf "$BUILD_REPO/vm-template/scripts/$script" 2>/dev/null)
    if [ -n "$NEW" ]; then
        echo "$NEW" > "$SCRIPTS_DIR/$script"
        chmod 755 "$SCRIPTS_DIR/$script"
        echo "[update] Updated: $script"
    fi
done

# -------------------------------------------------------
# 3. Update skill whitelist
# -------------------------------------------------------
echo "[update] Updating skill whitelist..."
NEW_WHITELIST=$(curl -sf "$BUILD_REPO/vm-template/approved-skills.txt" 2>/dev/null)
if [ -n "$NEW_WHITELIST" ]; then
    echo "$NEW_WHITELIST" > /opt/openclaw-skills-whitelist/approved-skills.txt
    echo "[update] Skill whitelist updated"
fi

# -------------------------------------------------------
# 4. Update installed OpenClaw skills (from whitelist)
# -------------------------------------------------------
echo "[update] Checking skill updates..."
OPENCLAW_SKILLS_DIR=$(openclaw config get skillsDir 2>/dev/null || echo "$HOME/.nvm/versions/node/v22.22.0/lib/node_modules/openclaw/skills")
while IFS= read -r skill; do
    # Skip comments and empty lines
    [[ "$skill" =~ ^#.*$ || -z "$skill" ]] && continue
    SKILL_MD=$(curl -sf "$SKILLS_REPO/$skill/SKILL.md" 2>/dev/null)
    if [ -n "$SKILL_MD" ]; then
        mkdir -p "$OPENCLAW_SKILLS_DIR/$skill"
        echo "$SKILL_MD" > "$OPENCLAW_SKILLS_DIR/$skill/SKILL.md"
        echo "[update] Skill updated: $skill"
    fi
done < /opt/openclaw-skills-whitelist/approved-skills.txt

# -------------------------------------------------------
# 5. Update OpenClaw itself (npm)
# -------------------------------------------------------
update_openclaw() {
    echo "[update] Checking OpenClaw npm update..."
    CURRENT_OC=$(openclaw --version 2>/dev/null || echo "unknown")
    npm install -g openclaw@latest --silent 2>/dev/null
    NEW_OC=$(openclaw --version 2>/dev/null || echo "unknown")
    if [ "$CURRENT_OC" != "$NEW_OC" ]; then
        echo "[update] OpenClaw updated: $CURRENT_OC → $NEW_OC"
        systemctl restart openclaw-gateway 2>/dev/null || true
    else
        echo "[update] OpenClaw already at latest ($CURRENT_OC)"
    fi
}
update_openclaw

# -------------------------------------------------------
# 6. Apply tier-specific updates if needed
# -------------------------------------------------------
NEW_TIER_SCRIPTS=$(echo "$MANIFEST" | python3 -c "
import sys, json
m = json.load(sys.stdin)
scripts = m.get('run_scripts', {})
print(scripts.get('ALL', ''))
" 2>/dev/null)
if [ -n "$NEW_TIER_SCRIPTS" ]; then
    echo "[update] Running manifest-specified scripts: $NEW_TIER_SCRIPTS"
    bash -c "$NEW_TIER_SCRIPTS"
fi

# -------------------------------------------------------
# 7. Restart OpenClaw gateway to pick up changes
# -------------------------------------------------------
echo "[update] Restarting OpenClaw gateway..."
systemctl restart openclaw-gateway 2>/dev/null || openclaw gateway restart 2>/dev/null || true

# -------------------------------------------------------
# 8. Save new version and state
# -------------------------------------------------------
echo "$LATEST_VERSION" > /opt/rightservers/version
python3 -c "
import json, datetime
state = {
    'version': '$LATEST_VERSION',
    'updated_at': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'tier': '$TIER',
    'hostname': '$(hostname)',
    'changelog': '$CHANGELOG'
}
print(json.dumps(state, indent=2))
" > "$STATE_FILE"

echo "[update] ✓ Update complete: $CURRENT_VERSION → $LATEST_VERSION"

# Reboot if required by manifest
if [ "$FORCE_REBOOT" = "True" ]; then
    echo "[update] Manifest requires reboot. Rebooting in 60s..."
    shutdown -r +1 "Right Servers update requires reboot"
fi

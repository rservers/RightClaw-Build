#!/bin/bash
# Right Servers — Fleet Manager
# Runs on the OpenClaw management VM (this machine).
# Queries WHMCS for all active OpenClaw VPS services, then:
#   - Pushes an immediate update trigger to all VMs, OR
#   - Reports status of all VMs
#
# Usage:
#   fleet-manager.sh update          — push update to all VMs
#   fleet-manager.sh update --tier PRO  — push to PRO+ only
#   fleet-manager.sh status           — show version/tier of all VMs
#   fleet-manager.sh run "command"    — run arbitrary command on all VMs
#   fleet-manager.sh vm <ip> "cmd"    — run command on one VM

WHMCS_API="https://portal.rightservers.com/includes/api.php"
WHMCS_ID="3Xub1JejTzN5vhWljvDRcEoYv2Ry1g6B"
WHMCS_SEC="ctaE7LEIov6UlD5qsOhR6mMmFC5eQ75u"
FLEET_KEY="$HOME/.ssh/rightservers_fleet"
SSH_USER="root"
SSH_OPTS="-i $FLEET_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
LOG="/var/log/rightservers-fleet.log"
MAX_PARALLEL=5  # Max concurrent SSH connections

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

# -------------------------------------------------------
# Get all active OpenClaw VPS IPs from WHMCS
# -------------------------------------------------------
get_fleet() {
    local tier_filter="${1:-}"
    log "Querying WHMCS for active OpenClaw VPS instances..."

    # Get all active services for OpenClaw products
    local result=$(curl -sf -X POST "$WHMCS_API" \
        -d "identifier=$WHMCS_ID" \
        -d "secret=$WHMCS_SEC" \
        -d "action=GetClientsProducts" \
        -d "responsetype=json" \
        -d "limitnum=250" \
        -d "status=Active" 2>/dev/null)

    # Filter to OpenClaw VPS products only, extract IPs
    echo "$result" | python3 -c "
import sys, json

data = json.load(sys.stdin)
products = data.get('products', {}).get('product', [])

tier_filter = '$tier_filter'.upper()
tier_rank = {'BASIC': 1, 'PRO': 2, 'ENTERPRISE': 3}

for p in products:
    name = p.get('name', '')
    if 'openclaw' not in name.lower():
        continue
    ip = p.get('dedicatedip') or p.get('assignedips', '').split(',')[0].strip()
    if not ip:
        continue
    # Determine tier from product name
    tier = 'BASIC'
    if 'enterprise' in name.lower(): tier = 'ENTERPRISE'
    elif 'pro' in name.lower(): tier = 'PRO'

    # Apply tier filter (include this tier and above)
    if tier_filter and tier_filter in tier_rank:
        if tier_rank.get(tier, 0) < tier_rank[tier_filter]:
            continue

    print(f'{ip}|{tier}|{p.get(\"id\",\"\")}|{name}')
" 2>/dev/null
}

# -------------------------------------------------------
# SSH into one VM and run a command
# -------------------------------------------------------
ssh_vm() {
    local ip="$1" cmd="$2"
    ssh $SSH_OPTS "$SSH_USER@$ip" "$cmd" 2>&1
}

# -------------------------------------------------------
# Run command on all VMs in parallel
# -------------------------------------------------------
fleet_run() {
    local cmd="$1" tier_filter="$2"
    local fleet=$(get_fleet "$tier_filter")
    local total=$(echo "$fleet" | grep -c '.' || echo 0)
    log "Running on $total VMs: $cmd"

    local pids=()
    local results_dir=$(mktemp -d)

    while IFS='|' read -r ip tier service_id name; do
        [ -z "$ip" ] && continue
        # Run in background, capture output
        (
            result=$(ssh_vm "$ip" "$cmd")
            echo "$ip|$tier|$result" > "$results_dir/$ip"
        ) &
        pids+=($!)

        # Throttle parallel connections
        if [ ${#pids[@]} -ge $MAX_PARALLEL ]; then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")
        fi
    done <<< "$fleet"

    # Wait for remaining
    wait

    # Print results
    local success=0 failed=0
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for result_file in "$results_dir"/*; do
        [ -f "$result_file" ] || continue
        IFS='|' read -r ip tier output < "$result_file"
        if [[ "$output" == *"error"* ]] || [[ "$output" == *"Connection refused"* ]]; then
            echo "  ❌ $ip [$tier]: $output"
            ((failed++))
        else
            echo "  ✅ $ip [$tier]: $output"
            ((success++))
        fi
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Total: $total | Success: $success | Failed: $failed"
    echo ""

    rm -rf "$results_dir"
    log "Fleet run complete: $success/$total succeeded"
}

# -------------------------------------------------------
# COMMANDS
# -------------------------------------------------------

case "${1:-help}" in

    update)
        TIER_FILTER="${3:-}"  # e.g. fleet-manager.sh update --tier PRO
        [[ "$2" == "--tier" ]] && TIER_FILTER="$3"
        log "=== FLEET UPDATE started (tier filter: ${TIER_FILTER:-ALL}) ==="
        fleet_run "/opt/rightservers/scripts/update.sh 2>&1 | tail -5" "$TIER_FILTER"
        log "=== FLEET UPDATE complete ==="
        ;;

    status)
        log "=== FLEET STATUS ==="
        fleet_run "echo \"\$(hostname) | v\$(cat /opt/rightservers/version 2>/dev/null || echo unknown) | \$(cat /opt/rightservers/tier 2>/dev/null || echo unknown) | uptime -p\"" ""
        ;;

    run)
        CMD="${2:-echo ok}"
        TIER_FILTER="${4:-}"
        [[ "$3" == "--tier" ]] && TIER_FILTER="$4"
        log "=== FLEET RUN: $CMD ==="
        fleet_run "$CMD" "$TIER_FILTER"
        ;;

    vm)
        IP="$2"
        CMD="${3:-echo ok}"
        log "Single VM [$IP]: $CMD"
        result=$(ssh_vm "$IP" "$CMD")
        echo "$result"
        ;;

    list)
        log "=== FLEET LIST ==="
        fleet=$(get_fleet)
        echo ""
        echo "  IP               | Tier       | Service ID | Product"
        echo "  ─────────────────┼────────────┼────────────┼────────────────────"
        while IFS='|' read -r ip tier sid name; do
            printf "  %-17s│ %-10s │ %-10s │ %s\n" "$ip" "$tier" "$sid" "$name"
        done <<< "$fleet"
        echo ""
        ;;

    publish)
        # Update the VERSION file and push to GitHub, triggering all VMs on next poll
        VERSION="${2:-}"
        CHANGELOG="${3:-Update}"
        if [ -z "$VERSION" ]; then
            echo "Usage: fleet-manager.sh publish <version> <changelog>"
            exit 1
        fi
        log "Publishing version $VERSION to GitHub..."
        VERSION_FILE="/home/rightclaw/RightClaw-Build/VERSION"
        python3 -c "
import json, datetime
v = json.load(open('$VERSION_FILE'))
v['version'] = '$VERSION'
v['released'] = datetime.date.today().isoformat()
v['changelog'] = '$CHANGELOG'
open('$VERSION_FILE','w').write(json.dumps(v, indent=2))
print('VERSION updated to $VERSION')
"
        cd /home/rightclaw/RightClaw-Build && \
        git add -A && \
        git commit -m "Release v$VERSION — $CHANGELOG" && \
        git push
        log "Published v$VERSION. VMs will auto-update on next poll (or run 'fleet-manager.sh update' to push immediately)."
        ;;

    help|*)
        echo ""
        echo "Right Servers Fleet Manager"
        echo ""
        echo "Usage:"
        echo "  fleet-manager.sh list                         List all active OpenClaw VMs"
        echo "  fleet-manager.sh status                       Show version/tier/uptime of all VMs"
        echo "  fleet-manager.sh update                       Push update to all VMs now"
        echo "  fleet-manager.sh update --tier PRO            Push update to PRO+ VMs only"
        echo "  fleet-manager.sh run \"command\"                Run command on all VMs"
        echo "  fleet-manager.sh run \"command\" --tier BASIC   Run on BASIC tier only"
        echo "  fleet-manager.sh vm <ip> \"command\"            Run command on one VM"
        echo "  fleet-manager.sh publish <ver> \"changelog\"    Bump VERSION + push to GitHub"
        echo ""
        ;;
esac

<?php
/**
 * Right Servers - OpenClaw VPS Post-Provisioning Hook
 *
 * HOW IT WORKS:
 * 1. Customer orders an OpenClaw VPS product (Basic, Pro, or Enterprise)
 * 2. AutoVM provisions the VM from your template (injects IP, hostname, password)
 * 3. WHMCS fires AfterModuleCreate — this hook intercepts it
 * 4. Hook SSHes into the new VM and runs the appropriate tier upgrade script
 * 5. Done — instance is fully configured for the customer's tier
 *
 * INSTALL:
 * Upload this file to: /home/portal/public_html/includes/hooks/rightservers_openclaw.php
 *
 * CONFIGURE:
 * Set the product group name and product names below to match your WHMCS products.
 */

// ============================================================
// CONFIGURATION — edit these to match your WHMCS product names
// ============================================================

// The WHMCS product group name for your OpenClaw VPS products
define('RS_PRODUCT_GROUP', 'Rightclaw');

// Map WHMCS product names → tier upgrade scripts on the VM
// Key = WHMCS product name (exact match)
// Value = script to run on the VM (or null for Basic — no extra script needed)
define('RS_TIER_MAP', json_encode([
    'Rightclaw Basic'      => null,
    'Rightclaw Pro'        => '/opt/rightservers/scripts/upgrade-pro.sh',
    'Rightclaw Enterprise' => '/opt/rightservers/scripts/upgrade-enterprise.sh',
]));

// SSH key path on the WHMCS server that has access to customer VMs
// Generate with: ssh-keygen -t ed25519 -f /root/.ssh/rightservers_deploy
// Then add the public key to the VM template's /root/.ssh/authorized_keys
// (template-prep.sh removes this — so you'll need AutoVM to inject it, OR
//  use password auth temporarily during first-boot, then the hook adds your key)
define('RS_SSH_KEY', '/root/.ssh/rightservers_deploy');

// Your deployer SSH username (root by default)
define('RS_SSH_USER', 'root');

// Max seconds to wait for VM to become reachable after AutoVM provisions it
// Hook will poll every 15s and proceed as soon as SSH is up — no unnecessary waiting
define('RS_BOOT_MAX_WAIT', 300);

// ============================================================
// HOOK: After Module Create (fires after AutoVM provisions VM)
// ============================================================

add_hook('AfterModuleCreate', 1, function ($vars) {
    $serviceId  = $vars['params']['serviceid'];
    $productName = $vars['params']['configoptions']['name'] ?? $vars['params']['product']['name'] ?? '';
    $serverIp    = $vars['params']['server']['ipaddress'] ?? '';
    $assignedIp  = $vars['params']['domain'] ?? $vars['params']['dedicatedip'] ?? '';
    $rootPass    = $vars['params']['password'] ?? '';

    // Only run for OpenClaw VPS products
    $groupName = $vars['params']['product']['groupname'] ?? '';
    if (stripos($groupName, 'rightclaw') === false && stripos($productName, 'rightclaw') === false) {
        return;
    }

    $tierMap = json_decode(RS_TIER_MAP, true);

    // Find matching tier script
    $tierScript = null;
    foreach ($tierMap as $product => $script) {
        if (stripos($productName, $product) !== false || $productName === $product) {
            $tierScript = $script;
            break;
        }
    }

    // Log that we're starting
    rs_log($serviceId, "OpenClaw post-provisioning started | Product: $productName | IP: $assignedIp");

    // Poll until VM is reachable via SSH (up to RS_BOOT_MAX_WAIT seconds)
    $targetIp = $assignedIp ?: $serverIp;
    if (empty($targetIp)) {
        rs_log($serviceId, "ERROR: Could not determine VM IP address. Manual tier activation required.");
        return;
    }

    // Poll for SSH availability — proceed as soon as VM responds, max RS_BOOT_MAX_WAIT seconds
    rs_log($serviceId, "Waiting for VM to come online (max " . RS_BOOT_MAX_WAIT . "s, polling every 15s)...");
    $ready = rs_wait_for_ssh($targetIp, RS_BOOT_MAX_WAIT, 15);
    if (!$ready) {
        rs_log($serviceId, "ERROR: VM at $targetIp did not come online within " . RS_BOOT_MAX_WAIT . "s. Manual tier activation required.");
        return;
    }

    // Run tier upgrade script if needed
    if ($tierScript !== null) {
        rs_log($serviceId, "Running tier script: $tierScript");
        $result = rs_ssh_exec($targetIp, $rootPass, $tierScript);
        rs_log($serviceId, "Tier script result: $result");
    } else {
        rs_log($serviceId, "Basic tier — no upgrade script needed.");
    }

    // Verify OpenClaw is running
    $check = rs_ssh_exec($targetIp, $rootPass, 'openclaw status 2>&1 | grep -E "Gateway|running" | head -3');
    rs_log($serviceId, "OpenClaw status check: $check");

    rs_log($serviceId, "Post-provisioning complete for service #$serviceId");
});

// ============================================================
// HOOK: After Module Suspend
// ============================================================

add_hook('AfterModuleSuspend', 1, function ($vars) {
    $serviceId = $vars['params']['serviceid'];
    $productName = $vars['params']['product']['name'] ?? '';
    if (stripos($productName, 'rightclaw') === false) return;

    $assignedIp = $vars['params']['dedicatedip'] ?? '';
    $rootPass   = $vars['params']['password'] ?? '';

    // Stop OpenClaw gateway on suspend
    rs_ssh_exec($assignedIp, $rootPass, 'openclaw gateway stop 2>/dev/null || true');
    rs_log($serviceId, "OpenClaw gateway stopped (suspended)");
});

// ============================================================
// HOOK: After Module Unsuspend
// ============================================================

add_hook('AfterModuleUnsuspend', 1, function ($vars) {
    $serviceId = $vars['params']['serviceid'];
    $productName = $vars['params']['product']['name'] ?? '';
    if (stripos($productName, 'rightclaw') === false) return;

    $assignedIp = $vars['params']['dedicatedip'] ?? '';
    $rootPass   = $vars['params']['password'] ?? '';

    // Restart OpenClaw gateway on unsuspend
    rs_ssh_exec($assignedIp, $rootPass, 'openclaw gateway start 2>/dev/null || true');
    rs_log($serviceId, "OpenClaw gateway started (unsuspended)");
});

// ============================================================
// HELPER: Execute command on VM via SSH
// Uses password auth as fallback since key may not be deployed yet
// ============================================================

function rs_ssh_exec($ip, $password, $command) {
    // Try SSH key first, fall back to password via sshpass
    $keyPath = RS_SSH_KEY;
    $user    = RS_SSH_USER;
    $opts    = "-o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes";

    if (file_exists($keyPath)) {
        $cmd = "ssh -i $keyPath $opts $user@$ip " . escapeshellarg($command) . " 2>&1";
    } else {
        // Fall back to sshpass (password auth)
        $cmd = "sshpass -p " . escapeshellarg($password) .
               " ssh $opts -o PreferredAuthentications=password $user@$ip " .
               escapeshellarg($command) . " 2>&1";
    }

    $output = shell_exec($cmd);
    return trim($output ?? 'no output');
}

// ============================================================
// HELPER: Poll until SSH port is open on the VM
// Returns true when ready, false if timed out
// ============================================================

function rs_wait_for_ssh($ip, $maxWait = 300, $interval = 15) {
    $start    = time();
    $attempts = 0;
    while ((time() - $start) < $maxWait) {
        $attempts++;
        $sock = @fsockopen($ip, 22, $errno, $errstr, 5);
        if ($sock) {
            fclose($sock);
            $elapsed = time() - $start;
            rs_log_raw("VM $ip is online after {$elapsed}s (attempt #$attempts)");
            return true;
        }
        rs_log_raw("VM $ip not ready yet (attempt #$attempts, {$errstr}), retrying in {$interval}s...");
        sleep($interval);
    }
    return false;
}

// ============================================================
// HELPER: Log to WHMCS activity log
// ============================================================

function rs_log($serviceId, $message) {
    logActivity("RightServers OpenClaw [Service #$serviceId]: $message");
}

function rs_log_raw($message) {
    logActivity("RightServers OpenClaw: $message");
}

<?php
/**
 * Right Servers - OpenClaw VPS Post-Provisioning Hook
 * Fires after AutoVM provisions a VM from the Rightclaw template.
 * Install: /home/portal/public_html/includes/hooks/rightservers_openclaw.php
 */

// ============================================================
// CONFIGURATION
// ============================================================

// Rightclaw product IDs — update if products are recreated
define('RS_PRODUCT_IDS', json_encode([
    155 => ['name' => 'Rightclaw Basic',      'script' => null],
    156 => ['name' => 'Rightclaw Pro',        'script' => '/opt/rightservers/scripts/upgrade-pro.sh'],
    157 => ['name' => 'Rightclaw Enterprise', 'script' => '/opt/rightservers/scripts/upgrade-enterprise.sh'],
]));

// Fleet SSH key on this server (cpanel11) — has access to all customer VMs
define('RS_SSH_KEY',  '/root/.ssh/rightservers_fleet');
define('RS_SSH_USER', 'root');

// Max seconds to wait for VM SSH to become reachable (polls every 15s)
define('RS_BOOT_MAX_WAIT', 300);

// ============================================================
// HOOK: After Module Create
// ============================================================

add_hook('AfterModuleCreate', 1, function ($vars) {
    $params    = $vars['params'];
    $serviceId = $params['serviceid'] ?? $params['accountid'] ?? 'unknown';
    $pid       = (int)($params['pid'] ?? $params['packageid'] ?? 0);
    $password  = $params['password'] ?? '';

    // Check if this is a Rightclaw product by PID
    $products = json_decode(RS_PRODUCT_IDS, true);
    if (!isset($products[$pid])) return; // Not a Rightclaw product

    $productName = $products[$pid]['name'];
    $tierScript  = $products[$pid]['script'];

    rs_log($serviceId, "Post-provisioning started | Product: $productName | PID: $pid");

    // Get IP — AutoVM populates dedicatedip; fall back to domain
    $targetIp = $params['dedicatedip'] ?? $params['domain'] ?? '';

    // If IP still empty, try fetching it from the service record
    if (empty($targetIp)) {
        rs_log($serviceId, "IP not in params — fetching from service record...");
        $targetIp = rs_get_service_ip($serviceId);
    }

    if (empty($targetIp)) {
        rs_log($serviceId, "ERROR: No IP found for service #$serviceId. Manual tier activation required.");
        return;
    }

    rs_log($serviceId, "Target IP: $targetIp — polling for SSH (max " . RS_BOOT_MAX_WAIT . "s)...");

    // Poll until SSH is up
    $ready = rs_wait_for_ssh($targetIp, $serviceId);
    if (!$ready) {
        rs_log($serviceId, "ERROR: VM did not come online within " . RS_BOOT_MAX_WAIT . "s. Manual activation required.");
        return;
    }

    // Basic tier — no upgrade script needed
    if ($tierScript === null) {
        rs_log($serviceId, "Basic tier — no upgrade script needed. Verifying OpenClaw...");
    } else {
        rs_log($serviceId, "Running tier script: $tierScript");
        $result = rs_ssh_exec($targetIp, $password, $tierScript . " 2>&1 | tail -5");
        rs_log($serviceId, "Tier result: $result");
    }

    // Verify OpenClaw is running
    $status = rs_ssh_exec($targetIp, $password, 'openclaw --version 2>/dev/null && openclaw gateway status 2>/dev/null | grep -E "running|active" | head -2 || echo "Gateway not yet started"');
    rs_log($serviceId, "OpenClaw: $status");

    rs_log($serviceId, "Post-provisioning complete for $productName (#$serviceId)");
});

// ============================================================
// HOOK: Suspend
// ============================================================

add_hook('AfterModuleSuspend', 1, function ($vars) {
    $params    = $vars['params'];
    $pid       = (int)($params['pid'] ?? $params['packageid'] ?? 0);
    $products  = json_decode(RS_PRODUCT_IDS, true);
    if (!isset($products[$pid])) return;

    $serviceId = $params['serviceid'] ?? 'unknown';
    $targetIp  = $params['dedicatedip'] ?? $params['domain'] ?? '';
    $password  = $params['password'] ?? '';

    rs_ssh_exec($targetIp, $password, 'openclaw gateway stop 2>/dev/null || true');
    rs_log($serviceId, "Gateway stopped (service suspended)");
});

// ============================================================
// HOOK: Unsuspend
// ============================================================

add_hook('AfterModuleUnsuspend', 1, function ($vars) {
    $params    = $vars['params'];
    $pid       = (int)($params['pid'] ?? $params['packageid'] ?? 0);
    $products  = json_decode(RS_PRODUCT_IDS, true);
    if (!isset($products[$pid])) return;

    $serviceId = $params['serviceid'] ?? 'unknown';
    $targetIp  = $params['dedicatedip'] ?? $params['domain'] ?? '';
    $password  = $params['password'] ?? '';

    rs_ssh_exec($targetIp, $password, 'openclaw gateway start 2>/dev/null || true');
    rs_log($serviceId, "Gateway started (service unsuspended)");
});

// ============================================================
// HELPERS
// ============================================================

function rs_get_service_ip($serviceId) {
    // Fetch the service record from WHMCS to get the assigned IP
    $result = localAPI('GetClientsProducts', ['serviceid' => $serviceId]);
    return $result['products']['product'][0]['dedicatedip'] ?? '';
}

function rs_wait_for_ssh($ip, $serviceId, $maxWait = RS_BOOT_MAX_WAIT, $interval = 15) {
    $start = time();
    $attempt = 0;
    while ((time() - $start) < $maxWait) {
        $attempt++;
        $sock = @fsockopen($ip, 22, $errno, $errstr, 5);
        if ($sock) {
            fclose($sock);
            $elapsed = time() - $start;
            rs_log($serviceId, "VM online after {$elapsed}s (attempt #$attempt)");
            return true;
        }
        rs_log($serviceId, "VM not ready (attempt #$attempt), retrying in {$interval}s...");
        sleep($interval);
    }
    return false;
}

function rs_ssh_exec($ip, $password, $command) {
    $keyPath = RS_SSH_KEY;
    $user    = RS_SSH_USER;
    $opts    = "-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes";

    if (file_exists($keyPath)) {
        $cmd = "ssh -i $keyPath $opts $user@$ip " . escapeshellarg($command) . " 2>&1";
    } else {
        $cmd = "sshpass -p " . escapeshellarg($password) .
               " ssh $opts -o PreferredAuthentications=password $user@$ip " .
               escapeshellarg($command) . " 2>&1";
    }
    return trim(shell_exec($cmd) ?? 'no output');
}

function rs_log($serviceId, $message) {
    logActivity("RightServers OpenClaw [#$serviceId]: $message");
}

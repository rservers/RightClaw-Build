<?php
/**
 * Right Servers - OpenClaw VPS Post-Provisioning Hook (DEBUG VERSION)
 */

add_hook('AfterModuleCreate', 1, function ($vars) {
    // Log everything immediately so we can see what's coming in
    $serviceId   = $vars['params']['serviceid'] ?? 'unknown';
    $productName = $vars['params']['product']['name'] ?? ($vars['params']['configoptions']['name'] ?? 'unknown');
    $groupName   = $vars['params']['product']['groupname'] ?? 'unknown';
    $moduleName  = $vars['params']['product']['servertype'] ?? ($vars['params']['modulename'] ?? 'unknown');
    $assignedIp  = $vars['params']['dedicatedip'] ?? ($vars['params']['domain'] ?? 'none');

    logActivity("RS DEBUG Hook fired - Service: $serviceId | Product: $productName | Group: $groupName | Module: $moduleName | IP: $assignedIp");

    // Bail if not a Rightclaw product
    if (stripos($groupName, 'rightclaw') === false && stripos($productName, 'rightclaw') === false) {
        logActivity("RS DEBUG - Not a Rightclaw product, skipping. Group: '$groupName' | Product: '$productName'");
        return;
    }

    logActivity("RS DEBUG - Rightclaw product confirmed, proceeding with provisioning");

    $tierMap = [
        'Rightclaw Basic'      => null,
        'Rightclaw Pro'        => '/opt/rightservers/scripts/upgrade-pro.sh',
        'Rightclaw Enterprise' => '/opt/rightservers/scripts/upgrade-enterprise.sh',
    ];

    $tierScript = null;
    foreach ($tierMap as $product => $script) {
        if (stripos($productName, $product) !== false) {
            $tierScript = $script;
            break;
        }
    }

    logActivity("RS DEBUG - Tier script: " . ($tierScript ?? 'none (Basic)'));

    $targetIp = $assignedIp;
    $rootPass = $vars['params']['password'] ?? '';

    logActivity("RS DEBUG - Target IP: '$targetIp' | Has password: " . (!empty($rootPass) ? 'yes' : 'no'));

    if (empty($targetIp) || $targetIp === 'none') {
        logActivity("RS DEBUG - No IP assigned yet, cannot SSH. Manual tier activation required for service #$serviceId");
        return;
    }

    if ($tierScript !== null) {
        logActivity("RS DEBUG - Would run: $tierScript on $targetIp");
    }

    logActivity("RS DEBUG - Hook complete for service #$serviceId");
});

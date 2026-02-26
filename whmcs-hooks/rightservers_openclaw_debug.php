<?php
/**
 * Right Servers - OpenClaw VPS Hook (DEBUG - dumps raw params)
 */

add_hook('AfterModuleCreate', 1, function ($vars) {
    // Dump the full params structure so we can see exactly what WHMCS passes
    $dump = json_encode($vars['params'] ?? [], JSON_PRETTY_PRINT);
    // Log in chunks (activity log has char limits)
    $chunks = str_split($dump, 200);
    foreach (array_slice($chunks, 0, 8) as $i => $chunk) {
        logActivity("RS PARAMS [$i]: $chunk");
    }
});

<?php

// A FrankenPHP worker: the script stays loaded, and handles one request per call.
$handler = static function (): void {
    echo hello_world($_GET['name'] ?? 'FrankenPHP');
};

while (frankenphp_handle_request($handler)) {
    gc_collect_cycles();
}

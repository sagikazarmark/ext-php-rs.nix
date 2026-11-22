<?php

// A request to PHP-FPM: each runs the script, in one of FPM's children.
echo hello_world($_GET['name'] ?? 'FPM');

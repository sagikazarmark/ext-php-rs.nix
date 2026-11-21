--TEST--
hello_world() greets by name
--EXTENSIONS--
hello
--FILE--
<?php
echo hello_world("Nix"), "\n";
?>
--EXPECT--
Hello, Nix!

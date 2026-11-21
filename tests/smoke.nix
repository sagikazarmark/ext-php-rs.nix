# A smoke test: `code` run with `php -r`, which must print `expected`. With `extension`, a
# module of buildRustPhpExtension, `php` loads it alone (php -n); otherwise `php` has it already
# (php.withExtensions).
{ lib, runCommand }:

{
  name,
  php,
  code,
  expected,
  extension ? null,
}:

runCommand "ext-php-rs-${name}"
  {
    inherit code expected;
    phpFlags = lib.optionals (extension != null) [
      "-n"
      "-d"
      "extension=${extension}/lib/php/extensions/${extension.extensionName}.so"
    ];
    __structuredAttrs = true;
  }
  ''
    result=$(${lib.getExe php} "''${phpFlags[@]}" -r "$code")
    echo "$result"
    if [ "$result" != "$expected" ]; then
      echo "expected: $expected" >&2
      exit 1
    fi
    touch "$out"
  ''

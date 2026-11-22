# Documented at runPhpTests in lib/default.nix (docs/functions.md).
{
  lib,
  runCommand,
}:

{
  php,
  extensions ? [ ],
  src,
  name ? "php-tests",
  # More arguments of run-tests.php.
  flags ? [ ],
}:

let
  withExtensions =
    if extensions == [ ] then php else php.withExtensions ({ enabled, ... }: enabled ++ extensions);
  # A PHP with extensions is a wrapper; run-tests.php is in its source.
  unwrapped = php.unwrapped or php;
in
runCommand "${name}-php${lib.versions.majorMinor php.version}"
  {
    nativeBuildInputs = [ withExtensions ];
    inherit flags;
    __structuredAttrs = true;
    env = {
      NO_INTERACTION = "1";
      REPORT_EXIT_STATUS = "1";
    };
  }
  ''
    tar -xf ${unwrapped.src} --strip-components=1 --wildcards '*/run-tests.php'
    # run-tests.php writes each test's output next to it.
    cp -r ${src} tests
    chmod -R u+w tests
    if [ -z "$(find tests -name '*.phpt')" ]; then
      echo "runPhpTests: no .phpt files in ${src}" >&2
      exit 1
    fi
    php run-tests.php -P -q --show-diff "''${flags[@]}" tests
    touch "$out"
  ''

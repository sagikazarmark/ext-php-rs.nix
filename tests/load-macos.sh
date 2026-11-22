#!/usr/bin/env bash
# Load the cross-built macOS archives in <dir> (devenv build outputs.load-tests) that are for the PHP
# on PATH (its minor, thread safety and the machine's CPU) into it, and run each extension's
# .phpt tests (<dir>/tests/<name>) with its run-tests.php, or <dir>/run-tests.php. For a macOS
# machine with a PHP that is not Nix's (Homebrew's, setup-php's).
#
# Usage: tests/load-macos.sh <dir>
set -euo pipefail

if [ $# -ne 1 ]; then
  sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
dir=$(cd "$1" && pwd)
# shellcheck source=lib/load-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/load-lib.sh"

php=$(php -n -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;')
ts=$(php -n -r 'echo PHP_ZTS ? "zts" : "nts";')
arch=$(uname -m)
[ "$arch" = aarch64 ] && arch=arm64
# PHP's own run-tests.php, where its build files are installed.
run_tests=$dir/run-tests.php
if prefix=$(php-config --prefix 2>/dev/null) && [ -f "$prefix/lib/php/build/run-tests.php" ]; then
  run_tests=$prefix/lib/php/build/run-tests.php
fi

shopt -s nullglob
archives=("$dir"/php_*_php"$php"-"$arch"-darwin-bsdlibc-"$ts".tgz)
if [ ${#archives[@]} -eq 0 ]; then
  echo "load-macos: no archives for PHP $php $ts $arch in $dir" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0
for archive in "${archives[@]}"; do
  asset=$(basename "$archive")
  name=$(extension_name "$archive")
  mkdir "$work/$name"
  tar -xzf "$archive" -C "$work/$name"
  cp -R "$dir/tests/$name" "$work/$name/tests"
  chmod -R u+w "$work/$name/tests"
  if NO_INTERACTION=1 REPORT_EXIT_STATUS=1 php -n "$run_tests" -P -q --show-diff \
    -n -d "extension=$work/$name/$name.so" "$work/$name/tests"; then
    echo "ok: $asset in $(command -v php) ($php $ts $arch)"
  else
    echo "FAILED: $asset in $(command -v php) ($php $ts $arch)" >&2
    failed=1
  fi
done
exit "$failed"

# shellcheck shell=bash
# Writes bin/php into a PHP headers output ($1, with include/php) for ext-php-rs's build
# script, which runs `$PHP -i` and never needs the target's PHP to run. It answers from the
# headers: the PHP version, the PHP API, thread safety and debug build, the four entries of
# `php -i` ext-php-rs reads. $2 is the shell for its shebang.
set -euo pipefail

out=$1
shell=$2
include=$out/include/php

define() {
  sed -n "s/^#define $1 \(.*\)$/\1/p" "$2" | head -n 1
}

version=$(define PHP_VERSION "$include/main/php_version.h" | tr -d '"')
api=$(define PHP_API_VERSION "$include/main/php.h")
if [ "$(define ZTS "$include/main/php_config.h")" = 1 ]; then thread_safety=enabled; else thread_safety=disabled; fi
if [ "$(define ZEND_DEBUG "$include/main/php_config.h")" = 1 ]; then debug=yes; else debug=no; fi

if [ -z "$version" ] || [ -z "$api" ]; then
  echo "write-php-stub: no PHP_VERSION or PHP_API_VERSION under $include" >&2
  exit 1
fi

mkdir -p "$out/bin"

cat >"$out/bin/php" <<EOF
#!$shell
# Not PHP: what ext-php-rs's build script reads from \`php -i\`, for the PHP of these headers.
case "\${1-}" in
  -i) printf '%s\n' 'PHP Version => $version' 'PHP API => $api' 'Thread Safety => $thread_safety' 'Debug Build => $debug' ;;
  *) echo "php stub: only -i is supported" >&2; exit 1 ;;
esac
EOF

chmod +x "$out/bin/php"

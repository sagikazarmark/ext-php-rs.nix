#!/usr/bin/env bash
# Install the cross-built archives in <dir> (devenv build outputs.load-tests) that are for one PHP with
# PIE (<dir>/pie.phar), the way a user would (`pie install`), into that PHP's official image,
# and run each extension's .phpt tests (<dir>/tests/<name>) there with the image's run-tests.php
# and the php.ini PIE leaves.
#
# PIE finds pre-packaged binaries among a GitHub release's assets through api.github.com. A
# stand-in for it (tests/pie-api.py) serves <dir> on the image's network, with a certificate
# the image trusts; each extension is a path repository (vendor ext-php-rs-nix, version from
# the archives' names). Needs Docker and openssl, on a machine of the archives' CPU (or with
# emulation, as Docker Desktop has).
#
# Usage: tests/pie.sh <dir> <php minor> <nts|zts> <x86_64|arm64> <glibc|musl>
set -euo pipefail

if [ $# -ne 5 ]; then
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
dir=$(cd "$1" && pwd) php=$2 ts=$3 arch=$4 libc=$5
tests=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/load-lib.sh
. "$tests/../lib/load-lib.sh"

image_for "$php" "$ts" "$arch" "$libc"
archives_for "$dir" "$php" "$ts" "$arch" "$libc"

work=$(mktemp -d)
network=ext-php-rs-pie-$$
cleanup() {
  docker rm -f "$network-api" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=api.github.com \
  -addext subjectAltName=DNS:api.github.com \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
chmod 644 "$work/key.pem"

# A path repository per extension, and the commands that install and test it.
script=$work/install.sh
cat >"$script" <<'EOF'
set -eu
# Trust the stand-in's certificate, and wait for it.
cp /work/cert.pem /usr/local/share/ca-certificates/api.github.com.crt
update-ca-certificates >/dev/null 2>&1
until php -r 'exit(@fsockopen("api.github.com", 443) ? 0 : 1);'; do sleep 0.2; done
failed=0
EOF
names=()
for archive in "${archives[@]}"; do
  asset=$(basename "$archive")
  name=$(extension_name "$archive")
  rest=${asset#php_"$name"-}
  version=${rest%%_php*}
  names+=("$name")
  mkdir -p "$work/packages/$name"
  cat >"$work/packages/$name/composer.json" <<EOF
{
  "name": "ext-php-rs-nix/$name",
  "type": "php-ext",
  "version": "$version",
  "license": "MIT",
  "php-ext": {
    "extension-name": "$name",
    "download-url-method": ["pre-packaged-binary"]
  }
}
EOF
  cat >>"$script" <<EOF
php /dist/pie.phar repository:add path /work/packages/$name >/dev/null
if php /dist/pie.phar install --no-interaction ext-php-rs-nix/$name; then
  # With the php.ini PIE leaves (no -n), from a copy: run-tests.php writes next to each test.
  cp -r /dist/tests/$name /tmp/tests-$name
  if NO_INTERACTION=1 REPORT_EXIT_STATUS=1 php /usr/local/lib/php/build/run-tests.php -P -q --show-diff /tmp/tests-$name; then
    echo "ok: $asset through PIE in $image"
  else
    echo "FAILED: $asset through PIE in $image" >&2
    failed=1
  fi
else
  echo "FAILED: pie install ext-php-rs-nix/$name ($asset) in $image" >&2
  failed=1
fi
EOF
done
# shellcheck disable=SC2016 # expands in the image's shell
echo 'exit "$failed"' >>"$script"

docker network create "$network" >/dev/null
docker run -d --name "$network-api" --network "$network" --network-alias api.github.com \
  -v "$dir:/assets:ro" -v "$work:/tls:ro" -v "$tests/pie-api.py:/pie-api.py:ro" \
  docker.io/library/python:3-alpine python /pie-api.py >/dev/null

docker run --rm --platform "$platform" --network "$network" \
  -v "$dir:/dist:ro" -v "$work:/work:ro" "$image" sh /work/install.sh

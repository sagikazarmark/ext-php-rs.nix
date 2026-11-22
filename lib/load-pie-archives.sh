#!/usr/bin/env bash
# Loads the Linux PIE archives in <archives> (mkPieRelease's output) into PHP's official Docker
# images, each into the image of its PHP version, thread safety, CPU and C library, and runs the
# .phpt tests in <tests> there with the image's run-tests.php, with the module loaded alone
# (php -n). An extension's tests are <tests>/<extension> if that exists (for archives of several
# extensions), otherwise <tests>.
#
# The options select the archives: --php <minor>, --ts <nts|zts>, --libc <glibc|musl> and
# --arch <x86_64|arm64>, this machine's by default (another needs emulation). DOCKER is the
# command to run (default: docker; podman works too).
#
# Usage: load-pie-archives [--php <minor>] [--ts <nts|zts>] [--libc <glibc|musl>]
#                          [--arch <x86_64|arm64>] <archives> <tests>
set -euo pipefail

usage() {
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

# shellcheck source=lib/load-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/load-lib.sh"

want_php='' want_ts='' want_libc='' want_arch=$(this_arch)
while [ $# -gt 0 ]; do
  case $1 in
  --php | --ts | --libc | --arch)
    [ $# -ge 2 ] || usage
    declare "want_${1#--}=$2"
    shift 2
    ;;
  -h | --help) usage ;;
  -*)
    echo "load-pie-archives: unknown option $1" >&2
    usage
    ;;
  *) break ;;
  esac
done
[ $# -eq 2 ] || usage
# Physical paths: a result symlink into the Nix store, mounted into the containers.
dir=$(cd "$1" && pwd -P) tests=$(cd "$2" && pwd -P)
docker=${DOCKER:-docker}

# selected: whether the archive parse_asset read is one the options select.
selected() {
  [ "$os" = linux ] && [ "$arch" = "$want_arch" ] &&
    { [ -z "$want_php" ] || [ "$php" = "$want_php" ]; } &&
    { [ -z "$want_ts" ] || [ "$ts" = "$want_ts" ]; } &&
    { [ -z "$want_libc" ] || [ "$libc" = "$want_libc" ]; }
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tested=0 failed=0
shopt -s nullglob
for archive in "$dir"/php_*.tgz; do
  parse_asset "$archive" || continue
  asset=$(basename "$archive")
  selected || continue
  if ! image_for "$php" "$ts" "$arch" "$libc" 2>/dev/null; then
    echo "skipped: $asset: PHP $php has no official $ts image (docker-library/php#1686)"
    continue
  fi

  extension_tests=$tests
  [ -d "$tests/$name" ] && extension_tests=$tests/$name
  if [ -z "$(find "$extension_tests" -name '*.phpt' -print -quit)" ]; then
    echo "load-pie-archives: no .phpt tests for $name in $extension_tests" >&2
    exit 1
  fi

  mkdir "$work/$asset"
  tar -xzf "$archive" -C "$work/$asset"
  tested=$((tested + 1))
  # The module alone (php -n), from the archive.
  if "$docker" run --rm --platform "$platform" \
    -v "$work/$asset:/check:ro" -v "$extension_tests:/tests:ro" "$image" \
    sh -c "$run_tests_in_image" sh -n -d "extension=/check/$name.so"; then
    echo "ok: $asset in $image"
  else
    echo "FAILED: $asset in $image" >&2
    failed=$((failed + 1))
  fi
done

if [ "$tested" -eq 0 ]; then
  echo "load-pie-archives: no Linux $want_arch archives${want_php:+ for PHP $want_php}${want_ts:+ $want_ts}${want_libc:+ $want_libc} in $dir" >&2
  exit 1
fi
echo "$((tested - failed)) of $tested archives passed"
[ "$failed" -eq 0 ]

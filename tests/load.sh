#!/usr/bin/env bash
# Load the cross-built archives in <dir> (devenv build outputs.load-tests) that are for one PHP into
# its official image, and run each extension's .phpt tests (<dir>/tests/<name>) there with the
# image's run-tests.php. Needs Docker, on a machine of the archives' CPU (or with emulation, as
# Docker Desktop has).
#
# Usage: tests/load.sh <dir> <php minor> <nts|zts> <x86_64|arm64> <glibc|musl>
set -euo pipefail

if [ $# -ne 5 ]; then
  sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
dir=$(cd "$1" && pwd) php=$2 ts=$3 arch=$4 libc=$5
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

image_for "$php" "$ts" "$arch" "$libc"
archives_for "$dir" "$php" "$ts" "$arch" "$libc"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0
for archive in "${archives[@]}"; do
  asset=$(basename "$archive")
  name=$(extension_name "$archive")
  mkdir "$work/$name"
  tar -xzf "$archive" -C "$work/$name"
  # The module alone (php -n), from the archive.
  if docker run --rm --platform "$platform" \
    -v "$work/$name:/check:ro" -v "$dir/tests/$name:/tests:ro" "$image" \
    sh -c "$run_tests_in_image" sh -n -d "extension=/check/$name.so"; then
    echo "ok: $asset in $image"
  else
    echo "FAILED: $asset in $image" >&2
    failed=1
  fi
done
exit "$failed"

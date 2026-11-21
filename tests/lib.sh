# shellcheck shell=bash disable=SC2034 # sets image, platform and archives for the scripts that source it
# What the scripts that load archives share: the official image for one PHP, its archives, and
# the extension an archive is of.

# image_for <php minor> <nts|zts> <x86_64|arm64> <glibc|musl>: sets image and platform, the
# official image of that PHP and its Docker platform.
image_for() {
  local php=$1 ts=$2 arch=$3 libc=$4 variant=cli distribution=trixie
  if [ "$(printf '%s\n' 8.6 "$php" | sort -V | head -n 1)" = 8.6 ]; then
    # From 8.6 the images are ZTS only, without a -zts variant (docker-library/php#1686).
    if [ "$ts" = nts ]; then
      echo "$(basename "$0"): PHP $php has no NTS official image (docker-library/php#1686)" >&2
      return 1
    fi
  else
    [ "$ts" = zts ] && variant=zts
  fi
  [ "$libc" = musl ] && distribution=alpine
  image=docker.io/library/php:$php-$variant-$distribution
  platform=linux/amd64
  [ "$arch" = arm64 ] && platform=linux/arm64
  return 0
}

# archives_for <dir> <php minor> <nts|zts> <x86_64|arm64> <glibc|musl>: sets archives, the
# Linux archives in <dir> for that PHP, or fails naming what it looked for.
archives_for() {
  local dir=$1 php=$2 ts=$3 arch=$4 libc=$5
  shopt -s nullglob
  archives=("$dir"/php_*_php"$php"-"$arch"-linux-"$libc"-"$ts".tgz)
  if [ ${#archives[@]} -eq 0 ]; then
    echo "$(basename "$0"): no archives for PHP $php $ts $arch $libc in $dir" >&2
    return 1
  fi
}

# extension_name <archive>: the extension of php_<extension>-<version>_…, whose name has no
# hyphens (PIE's extension names have none).
extension_name() {
  local name
  name=$(basename "$1")
  name=${name#php_}
  echo "${name%%-*}"
}

# A script for an official image's sh that runs the .phpt tests in /tests with the image's
# run-tests.php (which writes each test's output next to it, so from a copy), passing its
# arguments to run-tests.php: sh -c "$run_tests_in_image" sh <arguments>. First, PHP with those
# arguments must start without a word: run-tests.php skips the tests of an extension that does
# not load (one of the other thread safety, say), and passes.
# shellcheck disable=SC2016 # expands in the image's shell
run_tests_in_image='if ! out=$(php "$@" -r "" 2>&1) || [ -n "$out" ]; then printf "%s\n" "$out" >&2; exit 1; fi && cp -r /tests /tmp/tests && NO_INTERACTION=1 REPORT_EXIT_STATUS=1 php /usr/local/lib/php/build/run-tests.php -P -q --show-diff "$@" /tmp/tests'

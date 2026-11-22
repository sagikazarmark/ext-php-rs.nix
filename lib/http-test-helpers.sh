# shellcheck shell=bash
# The HTTP helpers of runFrankenphpTests' and runFpmTests' tests. $url is the server's address,
# which the runner exports.
# shellcheck disable=SC2154

# get <path> [curl arguments]: the response's body; fails with it on an HTTP error.
get() {
  local path=$1
  shift
  curl --silent --show-error --fail-with-body --max-time 30 "$@" "$url$path"
}

# expect <path> <body>: fails unless the response's body is <body> (without a trailing newline,
# as $(…) strips it).
expect() {
  local body
  # Returns itself: errexit is off in a function an `if` tests.
  body=$(get "$1") || return
  if [ "$body" != "$2" ]; then
    printf 'GET %s\n--- expected\n%s\n--- got\n%s\n' "$1" "$2" "$body" >&2
    return 1
  fi
}

# concurrently <n> <path>: <n> requests at once, which must all succeed.
concurrently() {
  local n=$1 path=$2 i pids=() failed=0
  for ((i = 0; i < n; i++)); do
    get "$path" >/dev/null &
    pids+=("$!")
  done
  for i in "${pids[@]}"; do
    wait "$i" || failed=1
  done
  if [ "$failed" -ne 0 ]; then
    echo "concurrently $n $path: a request failed" >&2
    return 1
  fi
}

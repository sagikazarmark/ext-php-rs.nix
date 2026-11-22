# Documented at runFrankenphpTests in lib/default.nix (docs/functions.md).
{
  lib,
  runCommand,
  writeText,
  curl,
}:

{
  # A FrankenPHP with the extensions to test, built for its PHP (frankenphp.override { php = …; }).
  frankenphp,
  # The document root.
  src,
  # The test: bash, with the helpers below.
  script,
  # The worker script in src, or null for classic mode (a request per script run).
  worker ? "index.php",
  workers ? 2,
  threads ? (if worker == null then 0 else workers) + 2,
  name ? "frankenphp-tests",
}:

let
  # The helpers the test calls, and the server's addresses ($url, $admin_url).
  helpers = writeText "frankenphp-test-helpers.sh" ''
    # get <path> [curl arguments]: the response's body; fails with it on an HTTP error.
    get() {
      local path=$1
      shift
      curl --silent --show-error --fail-with-body --max-time 30 "$@" "$url$path"
    }

    # expect <path> <body>: fails unless the response's body is <body> (without a trailing
    # newline, as $(…) strips it).
    expect() {
      local body
      body=$(get "$1")
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
      for i in "''${pids[@]}"; do
        wait "$i" || failed=1
      done
      if [ "$failed" -ne 0 ]; then
        echo "concurrently $n $path: a request failed" >&2
        return 1
      fi
    }

    # restart_workers: restarts the workers, as `frankenphp run --watch` and opcache_reset() do:
    # PHP shuts down and starts again in the same process (MSHUTDOWN, then MINIT).
    restart_workers() {
      curl --silent --show-error --fail-with-body --max-time 60 \
        -X POST "$admin_url/frankenphp/workers/restart"
    }
  '';
  test = writeText "frankenphp-test.sh" script;
in
assert lib.assertMsg (threads > (if worker == null then 0 else workers))
  "runFrankenphpTests: threads (${toString threads}) must be more than workers (${toString workers})";
runCommand name
  {
    nativeBuildInputs = [
      frankenphp
      curl
    ];
    inherit src worker;
    # The server listens on 127.0.0.1, which macOS's sandbox refuses otherwise.
    __darwinAllowLocalNetworking = true;
  }
  ''
    # Caddy keeps its configuration and data in these.
    export HOME=$TMPDIR XDG_CONFIG_HOME=$TMPDIR/config XDG_DATA_HOME=$TMPDIR/data
    cp -r "$src" app
    chmod -R u+w app
    root=$PWD/app
    if [ -n "$worker" ] && [ ! -f "app/$worker" ]; then
      echo "runFrankenphpTests: no worker script $worker in $src" >&2
      exit 1
    fi

    # PHP must start without a word: an extension that doesn't load (one built for a PHP without
    # thread safety, say) only warns, and the server doesn't log it.
    echo '<?php' > "$TMPDIR/empty.php"
    if ! startup=$(frankenphp php-cli "$TMPDIR/empty.php" 2>&1) || [ -n "$startup" ]; then
      printf '%s\n' "$startup" >&2
      echo "runFrankenphpTests: PHP did not start cleanly" >&2
      exit 1
    fi

    fail() {
      echo "runFrankenphpTests: $1" >&2
      echo "--- FrankenPHP's log" >&2
      tail -n 200 frankenphp.log >&2
      exit 1
    }

    # A free port, outside the sandbox too.
    for attempt in 1 2 3 4 5; do
      port=$((20000 + RANDOM % 20000))
      admin=$((port + 1))
      {
        echo "{"
        echo "  admin 127.0.0.1:$admin"
        echo "  persist_config off"
        echo "  auto_https off"
        echo "  frankenphp {"
        echo "    num_threads ${toString threads}"
        if [ -n "$worker" ]; then
          echo "    worker {"
          echo "      file $root/$worker"
          echo "      num ${toString workers}"
          echo "    }"
        fi
        echo "  }"
        echo "}"
        echo "http://127.0.0.1:$port {"
        echo "  root * $root"
        echo "  php_server"
        echo "}"
      } > Caddyfile
      frankenphp run --config Caddyfile --adapter caddyfile > frankenphp.log 2>&1 &
      pid=$!
      # Caddy logs this once every app (FrankenPHP's workers, the listeners) has started.
      for _ in $(seq 300); do
        if grep -q 'serving initial configuration' frankenphp.log || ! kill -0 "$pid" 2>/dev/null; then
          break
        fi
        sleep 0.1
      done
      if kill -0 "$pid" 2>/dev/null; then
        break
      fi
      wait "$pid" || true
      if ! grep -q 'address already in use' frankenphp.log; then
        fail "FrankenPHP did not start"
      fi
    done
    kill -0 "$pid" 2>/dev/null || fail "FrankenPHP did not start"
    grep -q 'serving initial configuration' frankenphp.log || fail "FrankenPHP did not start in 30 seconds"

    # In a bash of its own: errexit is off throughout a command `if` tests, a subshell's
    # `set -e` included, so a failing command in the test would not stop it.
    export url=http://127.0.0.1:$port admin_url=http://127.0.0.1:$admin
    if ! "$BASH" -euo pipefail -c '. "$1"; . "$2"' test ${helpers} ${test}; then
      fail "the test failed"
    fi

    kill -0 "$pid" 2>/dev/null || fail "FrankenPHP exited during the test"
    # Shutting down runs every module's shutdown.
    kill -TERM "$pid"
    status=0
    wait "$pid" || status=$?
    [ "$status" -eq 0 ] || fail "FrankenPHP exited with $status on shutdown"
    touch "$out"
  ''

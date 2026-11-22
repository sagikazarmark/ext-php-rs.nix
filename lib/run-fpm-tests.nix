# Documented at runFpmTests in lib/default.nix (docs/functions.md).
{
  lib,
  runCommand,
  writeText,
  caddy,
  curl,
}:

{
  php,
  extensions ? [ ],
  # The document root.
  src,
  # The test: bash, with the helpers of http-test-helpers.sh and below.
  script,
  # pm.max_children: pm is static, so FPM forks them all at startup.
  children ? 2,
  # pm.max_requests: each child exits after this many requests (0: never).
  maxRequests ? 0,
  # More pool settings: { "php_admin_value[memory_limit]" = "256M"; }.
  settings ? { },
  name ? "fpm-tests",
}:

let
  withExtensions =
    if extensions == [ ] then php else php.withExtensions ({ enabled, ... }: enabled ++ extensions);

  pool = lib.concatStrings (
    lib.mapAttrsToList (key: value: "${key} = ${toString value}\n") (
      {
        pm = "static";
        "pm.max_children" = children;
        "pm.max_requests" = maxRequests;
        # A child's stderr in FPM's log.
        catch_workers_output = "yes";
      }
      // settings
    )
  );

  # FPM's helper, besides the HTTP ones. $fpm_pid is FPM's master, $fpm_log its log, and
  # $startup_log PHP's errors as the master starts.
  helpers = writeText "fpm-test-helpers.sh" ''
    # reload: reloads FPM (SIGUSR2), as `systemctl reload php-fpm` does: the children exit
    # (MSHUTDOWN in each), and the master runs itself again (exec), so it loads the extensions
    # again (MINIT) and forks new children. Returns once they're ready, and fails if PHP
    # warned as it started again.
    reload() {
      local before
      before=$(grep -c 'ready to handle connections' "$fpm_log" || true)
      kill -USR2 "$fpm_pid"
      for _ in $(seq 300); do
        if [ "$(grep -c 'ready to handle connections' "$fpm_log" || true)" -gt "$before" ]; then
          if [ -s "$startup_log" ]; then
            cat "$startup_log" >&2
            echo "reload: PHP did not start cleanly" >&2
            return 1
          fi
          return 0
        fi
        if ! kill -0 "$fpm_pid" 2>/dev/null; then
          echo "reload: FPM exited" >&2
          return 1
        fi
        sleep 0.1
      done
      echo "reload: FPM did not reload in 30 seconds" >&2
      return 1
    }
  '';
  test = writeText "fpm-test.sh" script;
in
assert lib.assertMsg (children > 0) "runFpmTests: children must be at least 1";
runCommand "${name}-php${lib.versions.majorMinor php.version}"
  {
    nativeBuildInputs = [
      withExtensions
      caddy
      curl
    ];
    inherit src pool;
    # The servers listen on 127.0.0.1, which macOS's sandbox refuses otherwise.
    __darwinAllowLocalNetworking = true;
  }
  ''
    # Caddy keeps its configuration and data in these.
    export HOME=$TMPDIR XDG_CONFIG_HOME=$TMPDIR/config XDG_DATA_HOME=$TMPDIR/data
    cp -r "$src" app
    chmod -R u+w app
    root=$PWD/app
    fpm_log=$PWD/fpm.log
    startup_log=$PWD/startup.log

    # PHP must start without a word: an extension that doesn't load only warns. FPM's master
    # drops PHP's startup errors without an error_log (startup_log below), and the CLI shows
    # anything else an extension prints.
    echo '<?php' > "$TMPDIR/empty.php"
    if ! startup=$(php "$TMPDIR/empty.php" 2>&1) || [ -n "$startup" ]; then
      printf '%s\n' "$startup" >&2
      echo "runFpmTests: PHP did not start cleanly" >&2
      exit 1
    fi

    fail() {
      echo "runFpmTests: $1" >&2
      for log in startup.log fpm.log fpm.out php.log caddy.log; do
        if [ -s "$log" ]; then
          echo "--- $log" >&2
          tail -n 200 "$log" >&2
        fi
      done
      exit 1
    }

    # FPM logs a warning for a child that crashed (a signal other than SIGQUIT, which it stops
    # them with) or that exited with an error: it starts another, and the request only fails.
    # It logs nothing for the children it stops to reload or exit. A child exits (and crashes,
    # in MSHUTDOWN) after its last response, so this waits for FPM's log to be quiet for a
    # second first (30 at most).
    check_children() {
      local size quiet=0
      for _ in $(seq 300); do
        size=$(wc -c < fpm.log)
        sleep 0.1
        if [ "$(wc -c < fpm.log)" -eq "$size" ]; then
          quiet=$((quiet + 1))
          [ "$quiet" -lt 10 ] || break
        else
          quiet=0
        fi
      done
      if grep -E '\] child [0-9]+ exited' fpm.log | grep -v NOTICE >&2; then
        fail "a child of FPM crashed"
      fi
    }

    # wait_for <pid> <log> <message>: until the process logs <message>, exits, or 30 seconds pass.
    wait_for() {
      for _ in $(seq 300); do
        if grep -qs "$3" "$2" || ! kill -0 "$1" 2>/dev/null; then
          break
        fi
        sleep 0.1
      done
    }

    # Free ports, outside the sandbox too: Caddy's, and FPM's after it.
    started=
    for attempt in 1 2 3 4 5; do
      port=$((20000 + RANDOM % 20000))
      fpm_port=$((port + 1))

      {
        echo "[global]"
        echo "error_log = $fpm_log"
        echo "daemonize = no"
        # Children that don't stop in 10 seconds are killed, rather than holding up the check.
        echo "process_control_timeout = 10"
        echo "[test]"
        echo "listen = 127.0.0.1:$fpm_port"
        echo "php_admin_value[error_log] = $PWD/php.log"
        echo "php_admin_flag[log_errors] = on"
        printf '%s' "$pool"
      } > fpm.conf
      rm -f fpm.log startup.log
      # -R: the sandbox's user may be root. The master's PHP logs its errors to startup.log, the
      # children's to php.log (the pool's error_log). A reload runs the same command.
      php-fpm --nodaemonize --allow-to-run-as-root --fpm-config fpm.conf \
        -d log_errors=1 -d error_log="$startup_log" > fpm.out 2>&1 &
      fpm_pid=$!
      wait_for "$fpm_pid" fpm.log 'ready to handle connections'
      if ! kill -0 "$fpm_pid" 2>/dev/null; then
        wait "$fpm_pid" || true
        if grep -qi 'address already in use' fpm.log fpm.out 2>/dev/null; then
          continue
        fi
        fail "FPM did not start"
      fi
      grep -q 'ready to handle connections' fpm.log || fail "FPM did not start in 30 seconds"
      [ ! -s startup.log ] || fail "PHP did not start cleanly in FPM"

      {
        echo "{"
        echo "  admin off"
        echo "  persist_config off"
        echo "  auto_https off"
        echo "}"
        echo "http://127.0.0.1:$port {"
        echo "  root * $root"
        echo "  php_fastcgi 127.0.0.1:$fpm_port"
        echo "  file_server"
        echo "}"
      } > Caddyfile
      caddy run --config Caddyfile --adapter caddyfile > caddy.log 2>&1 &
      caddy_pid=$!
      wait_for "$caddy_pid" caddy.log 'serving initial configuration'
      if kill -0 "$caddy_pid" 2>/dev/null; then
        grep -q 'serving initial configuration' caddy.log || fail "Caddy did not start in 30 seconds"
        started=1
        break
      fi
      wait "$caddy_pid" || true
      grep -q 'address already in use' caddy.log || fail "Caddy did not start"
      kill -QUIT "$fpm_pid"
      wait "$fpm_pid" || true
    done
    [ -n "$started" ] || fail "no free port in 5 attempts"

    # In a bash of its own: errexit is off throughout a command `if` tests, a subshell's
    # `set -e` included, so a failing command in the test would not stop it.
    export url=http://127.0.0.1:$port fpm_pid fpm_log startup_log
    if ! "$BASH" -euo pipefail -c '. "$1"; . "$2"; . "$3"' test ${./http-test-helpers.sh} ${helpers} ${test}; then
      fail "the test failed"
    fi

    kill -0 "$fpm_pid" 2>/dev/null || fail "FPM exited during the test"
    check_children
    # A graceful stop: each child finishes its request and exits (MSHUTDOWN).
    kill -QUIT "$fpm_pid"
    wait_for "$fpm_pid" fpm.log 'exiting, bye-bye'
    if kill -0 "$fpm_pid" 2>/dev/null; then
      sleep 1
      kill -0 "$fpm_pid" 2>/dev/null && fail "FPM did not stop in 30 seconds"
    fi
    status=0
    wait "$fpm_pid" || status=$?
    [ "$status" -eq 0 ] || fail "FPM exited with $status on shutdown"
    touch "$out"
  ''

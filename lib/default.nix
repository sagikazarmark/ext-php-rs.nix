/**
  The functions for one package set, and the tools they build with. Get it with
  [`ext-php-rs.lib.makeRustPhpPlatform`](#ext-php-rslibmakerustphpplatform), from the overlay
  (`pkgs.rustPhpPlatform`), or with `pkgs.callPackage ./lib { … }`.

  It's a scope (`lib.makeScope`): change any of its attributes, such as `rustToolchain`,
  with `rustPhpPlatform.overrideScope (final: prev: { … })`.

  # Inputs

  - `rustToolchain`: The Rust toolchain (rustc and cargo). Default: nixpkgs' rustc and cargo. Portable builds
    need each target's standard library: rust-overlay's toolchains get it added
    automatically, any other toolchain must already have it. With nixpkgs' Rust, portable
    builds use rust-overlay's latest stable toolchain if its overlay is applied (`pkgs.rust-bin`),
    and native builds keep nixpkgs' Rust.
  - `zig`: The zig that portable builds compile and link with. Default: `pkgs.zig`.
*/
{
  lib,
  stdenv,
  newScope,
  symlinkJoin,
  mkShell,
  rustc,
  cargo,
  rustPlatform,
  makeRustPlatform,
  zig,
  cargo-zigbuild,
  fetchFromGitHub,
  apple-sdk,
  rustToolchain ? null,
  # rust-overlay's toolchains, where its overlay is applied (pkgs.rust-bin): portable builds
  # use its latest stable one when rustToolchain is nixpkgs' Rust.
  rust-bin ? null,
}:

lib.makeScope newScope (
  self:
  let
    pie = self.callPackage ./pie.nix { };
  in
  {
    /**
      Builds a PHP extension written in Rust with ext-php-rs. It extends the scope's
      `rustPlatform.buildRustPackage`, and takes its arguments too.

      - **Without a `target`**, it builds the way `buildRustPackage` does, for the package set's
        host platform and against `php`: a package for `php.withExtensions`. From
        `pkgsCross.<platform>.callPackage`, that's another Nix platform's PHP.
      - **With a `target`**, it's a portable build: cross-compiled from any platform, it loads
        in any PHP of that target and thread safety, not only Nix's. See
        [How a portable build works](portable-builds.md).

      The derivation is named `php-<pname>-<version>`, as nixpkgs names its PHP extensions.

      # Inputs

      - `php`: The PHP to build against. With a `target`, only its version matters: the build uses
        that version's headers, configured for the target.
      - `target`: For a portable build, a target from [`targets`](#rustphpplatformtargets) or
        [`mkTarget`](#rustphpplatformmktarget). This is a compile target for Cargo, not Nix's
        `targetPlatform`.
      - `threadSafety`: For a portable build, the thread safety of the PHP to build for: `"nts"` or
        `"zts"` (thread-safe), as PIE names the archives. Without a target, `php`'s own thread
        safety is used.
      - `pname`, `version`, `src`: As for `buildRustPackage`.
      - `cargoHash`, `cargoLock` or `cargoDeps`: The Cargo dependencies, as for `buildRustPackage`.
      - `cargoPackage`: The Cargo package to build. Default: `pname`.
      - `extensionName`: The PHP module's name, as `extension=` loads it. Default: `cargoPackage`.
      - `libName`: The cdylib's name (`[lib] name` in `Cargo.toml`). Default: `cargoPackage`, with `-`
        replaced by `_`.
      - `allowedLibraries`: For a portable build, the shared libraries the module may link to. Default: the
        target's C library (on macOS, the system's libraries and frameworks).

      Other arguments are `buildRustPackage`'s: `buildType` (`"release"` or `"debug"`),
      `buildFeatures`, `buildNoDefaultFeatures`, `buildAndTestSubdir`, `cargoBuildFlags`, …
      Its tests are off (`doCheck = false`): a module's tests need PHP's embed SAPI.

      # Output

      - `lib/php/extensions/<extensionName>.so`: the module.
      - `share/ext-php-rs/bindings.rs`: the Zend API as bindgen generated it, to compare
        builds against other headers.
      - `passthru`: `extensionName`, `phpVersion`, `threadSafety` (`"nts"` or `"zts"`), `target`
        and `headers`.

      The builds set the rustflags an ext-php-rs module needs (`-undefined dynamic_lookup` on
      macOS, no static C library on musl), on top of a project's own `.cargo/config.toml`.

      # Install check

      Without a target, the module is loaded into `php`. With one, the check reads the module:
      it may only need the C library (on macOS, the system's libraries and frameworks), no glibc
      symbol newer than the target's floor and no newer macOS than its minimum. It's also loaded
      into `php` when `php` is of the target's platform (OS, CPU, C library and thread safety).

      # Examples

      ```nix
      # For php.withExtensions ({ enabled, ... }: enabled ++ [ hello ]).
      hello = rustPhpPlatform.buildRustPhpExtension {
        pname = "hello";
        version = "0.1.0";
        src = ./.;
        cargoLock.lockFile = ./Cargo.lock;
        php = pkgs.php84;
      };
      ```

      ```nix
      # For PHP 8.4 ZTS on Linux arm64 with musl, built on any platform.
      hello-musl = rustPhpPlatform.buildRustPhpExtension {
        # …
        php = pkgs.php84;
        target = rustPhpPlatform.targets.aarch64-linux-musl;
        threadSafety = "zts";
      };
      ```
    */
    buildRustPhpExtension = self.callPackage ./build-extension { };

    /**
      Builds one extension for every combination of PHP version, thread safety, target and
      variant: portable builds of `args` (`buildRustPhpExtension` with a `target`), as a nested
      attribute set.

      ```
      <php>.<threadSafety>.<target>.<variant>
      php84.zts.x86_64-linux-glibc.release
      ```

      - `<php>`: `php` followed by the PHP's major and minor version (`php84`), whatever attribute
        the PHP came from: a portable build is for a PHP minor.
      - `<threadSafety>`: `nts` or `zts`.
      - `<target>`: the target's name (`x86_64-linux-glibc`, `aarch64-darwin`), including for a
        [`mkTarget`](#rustphpplatformmktarget) one.
      - `<variant>`: a name of `variants`, `release` by default.

      Two PHPs of the same minor, or two targets of the same name, are refused. Each extension is
      evaluated only when it's used, so a project can list more than it builds. Builds without
      a target are `buildRustPhpExtension`'s (or
      [`mkPhpExtensionsOverlay`](#ext-php-rslibmkphpextensionsoverlay)'s), for each PHP itself.

      [`collectExtensions`](#rustphpplatformcollectextensions) makes a list of them, and
      [`buildPieRelease`](#rustphpplatformbuildpierelease) is the release variant of the same
      builds as PIE archives: with the same `args`, they're the same derivations.

      # Inputs

      - `args`: `buildRustPhpExtension`'s arguments, without `php`, `target` and `threadSafety`.
      - `php`: The PHPs to build for (a list).
      - `targets`: The targets to build for. Default: every one of [`targets`](#rustphpplatformtargets).
      - `threadSafety`: Default: `[ "nts" "zts" ]`.
      - `variants`: Builds of each combination, by name: each one more `buildRustPhpExtension`
        arguments, merged over `args` (`args // variant`, so a variant's `buildFeatures` replace
        those of `args`). Default: `{ release = { }; }`, `args` alone.

      # Example

      ```nix
      extensions = rustPhpPlatform.buildRustPhpExtensions {
        args = ext-php-rs.lib.extensionArgs { root = ./.; };
        php = [ pkgs.php84 pkgs.php85 ];
        targets = with rustPhpPlatform.targets; [ x86_64-linux-glibc aarch64-linux-glibc ];
        variants = {
          release = { };
          debug = { buildType = "debug"; };
          debug-diagnostics = { buildType = "debug"; buildFeatures = [ "diagnostics" ]; };
        };
      };
      # nix build .#extensions.php84.zts.x86_64-linux-glibc.debug, from legacyPackages (which
      # `nix flake check` and `nix flake show` don't list).
      legacyPackages.${system} = { inherit extensions; };
      # The release variant as PIE archives: the same derivations.
      packages.${system}.pie = rustPhpPlatform.mkPieRelease {
        extensions = rustPhpPlatform.collectExtensions extensions { variant = "release"; };
      };
      ```
    */
    buildRustPhpExtensions = self.callPackage ./build-extensions.nix { };

    /**
      The extensions of a [`buildRustPhpExtensions`](#rustphpplatformbuildrustphpextensions) set
      as a list, filtered by any of its levels and by the target's OS, CPU and C library:
      `collectExtensions extensions filter`.

      Also available as [`ext-php-rs.lib.collectExtensions`](#ext-php-rslibcollectextensions),
      without a package set.

      # Inputs

      - `extensions`: A `buildRustPhpExtensions` set, or any set of extensions built with a
        `target`, of its shape (`<php>.<threadSafety>.<target>.<variant>`).
      - `filter`: An attribute set; `{ }` collects every extension. Each attribute is a value or a
        list of values, of which the extension must have one:
        - `php`: the key of the PHP, such as `"php84"`
        - `threadSafety`: `"nts"` or `"zts"`
        - `target`: the target's name, such as `"x86_64-linux-glibc"`
        - `variant`: the variant's name
        - `arch`, `os`, `libc`: the target's (as [`mkTarget`](#rustphpplatformmktarget) takes
          them: `"aarch64"`, `"linux"`, `"musl"`)

      # Examples

      ```nix
      rustPhpPlatform.collectExtensions extensions { variant = "release"; }
      ```

      ```nix
      # The debug builds for glibc, for PHP 8.4 and 8.5.
      rustPhpPlatform.collectExtensions extensions {
        variant = "debug";
        libc = "glibc";
        php = [ "php84" "php85" ];
      }
      ```
    */
    collectExtensions = import ./collect-extensions.nix { inherit lib; };

    /**
      A derivation that depends on everything some extensions build with but their source: the
      Rust toolchain, zig, the PHP headers, the Cargo dependencies, …, each extension's
      `inputDerivation` without `src`. Building it fetches (or builds) all of that, so that
      building the extensions afterwards only compiles them: a Docker layer that changes only
      when the dependencies do, a CI cache to warm up, a binary cache to push to.

      The source isn't evaluated either, so the file set of
      [`extensionArgs`](#rustphpplatformextensionargs) needn't exist yet: Nix evaluates the
      inputs from `flake.nix`, `flake.lock`, `Cargo.toml`, `Cargo.lock` and `composer.json`
      alone. That needs `cargoLock` (as `extensionArgs` sets it) or `cargoDeps`: with
      `cargoHash`, `buildRustPackage` vendors the dependencies from the source.

      The output is a file with the path of each `inputDerivation`.

      # Inputs

      - `extensions`: The extensions (a list), such as
        [`collectExtensions`](#rustphpplatformcollectextensions)'s.
      - `name`: Default: `"php-extension-inputs"`.

      # Example

      In `flake.nix`, with `extensions` from
      [`buildRustPhpExtensions`](#rustphpplatformbuildrustphpextensions) in `legacyPackages`:

      ```nix
      # Everything the Linux builds need.
      packages.${system}.extension-inputs = rustPhpPlatform.mkExtensionInputs {
        extensions = rustPhpPlatform.collectExtensions extensions { os = "linux"; };
      };
      ```

      A `Dockerfile` that builds one of them for PHP 8.4 ZTS and the image's CPU, then installs it
      into PHP's official image. Nix runs on the build machine's CPU (`$BUILDPLATFORM`) and
      cross-compiles for the image's. The first `nix build` runs again only when the files it's
      given change, for images of any CPU, and the second then only compiles the extension. Leave
      `result` and `target` out with `.dockerignore`.

      ```dockerfile
      FROM --platform=$BUILDPLATFORM docker.io/nixos/nix:latest AS build
      RUN printf '%s\n' \
            'experimental-features = nix-command flakes' \
            'extra-substituters = https://ext-php-rs.cachix.org' \
            'extra-trusted-public-keys = ext-php-rs.cachix.org-1:PtGECZQzLu6AvwSPiiOkfXYVvsb7sd0Ckc8gyvVhfrU=' \
            >> /etc/nix/nix.conf
      WORKDIR /src
      # What Nix evaluates the inputs from: not the extension's source.
      COPY flake.nix flake.lock Cargo.toml Cargo.lock composer.json ./
      RUN nix build .#extension-inputs --no-link
      COPY . .
      # The image's CPU, amd64 or arm64: declared here, so that the layers above are the same for
      # every image.
      ARG TARGETARCH
      RUN arch=$([ "$TARGETARCH" = arm64 ] && echo aarch64 || echo x86_64) \
          && nix build ".#extensions.php84.zts.$arch-linux-glibc.release" \
          && cp result/lib/php/extensions/hello.so /hello.so

      FROM docker.io/library/php:8.4-zts-bookworm
      COPY --from=build /hello.so /tmp/
      RUN mv /tmp/hello.so "$(php -r 'echo ini_get("extension_dir");')/" \
          && docker-php-ext-enable hello
      ```
    */
    mkExtensionInputs = self.callPackage ./extension-inputs.nix { };

    /**
      Reads `buildRustPhpExtension`'s arguments from a project's files:
      - `pname` and `version`: from `Cargo.toml`'s `[package]` (a version inherited from the
        workspace too).
      - `extensionName`: `composer.json`'s `php-ext.extension-name`, which PIE names the
        archives and the module after; without one, the Cargo package's name, which
        ext-php-rs names the module after.
      - `libName`: `Cargo.toml`'s `[lib] name`, if it has one.
      - `cargoLock.lockFile`: the workspace's `Cargo.lock`.
      - `src`: only what the build reads (`Cargo.toml`, `Cargo.lock`, `src/`, and `build.rs` and
        `.cargo/` if they exist), so that changing tests, CI or docs rebuilds nothing. For a
        crate in a workspace, the whole workspace.

      Also available as [`ext-php-rs.lib.extensionArgs`](#ext-php-rslibextensionargs), without a package
      set.

      # Inputs

      - `root`: The crate's directory, with its `Cargo.toml`.
      - `workspace`: For a crate in a workspace, the workspace's directory: its `[workspace.package]`,
        `Cargo.lock` and `composer.json`. Default: `root`.
      - `src`: The source to build, for another layout (files the code includes, a narrower
        workspace).

      Any other argument is passed through, and overrides what is read.

      # Examples

      ```nix
      args = ext-php-rs.lib.extensionArgs { root = ./.; };
      hello = rustPhpPlatform.buildRustPhpExtension (args // { php = pkgs.php84; });
      ```

      ```nix
      args = ext-php-rs.lib.extensionArgs {
        root = ./crates/hello;
        workspace = ./.;
        buildFeatures = [ "tokio" ];
      };
      ```
    */
    extensionArgs = import ./extension-args.nix { inherit lib; };

    /**
      Builds a release of one extension for [PIE](https://github.com/php/pie): `args` built
      for every combination of `php`, `targets` and `threadSafety`, as one
      [`mkPieRelease`](#rustphpplatformmkpierelease).

      # Inputs

      - `args`: `buildRustPhpExtension`'s arguments, without `php`, `target` and `threadSafety`.
      - `php`: The PHPs to build for (a list): one archive per PHP minor.
      - `targets`: The targets to build for. Default: every one of [`targets`](#rustphpplatformtargets).
      - `threadSafety`: Default: `[ "nts" "zts" ]`.
      - `name`: The derivation's name. Default: `mkPieRelease`'s.

      # Example

      ```nix
      # Every target, NTS and ZTS, for PHP 8.4 and 8.5: 24 archives.
      pie = rustPhpPlatform.buildPieRelease {
        args = ext-php-rs.lib.extensionArgs { root = ./.; };
        php = [ pkgs.php84 pkgs.php85 ];
      };
      ```
    */
    buildPieRelease = pie.buildPieRelease;

    /**
      Collects portable builds into a release for [PIE](https://github.com/php/pie): a
      directory with one archive per extension, each with its `.sha256` file, and `SHA256SUMS`.
      The archives are named the way `pie install` looks for them among a GitHub release's
      assets, such as `php_hello-0.1.0_php8.4-arm64-linux-musl-zts.tgz`.

      `passthru.archives` has each archive's derivation.

      # Inputs

      - `extensions`: Extensions built with a `target`. Each combination of PHP minor, target and thread
        safety may appear only once.
      - `name`: The derivation's name. Default: `php-<pname>-<version>-pie`, which needs every
        extension to be of the same package and version.

      # Example

      ```nix
      pie = rustPhpPlatform.mkPieRelease { extensions = [ hello-musl hello-darwin ]; };
      ```
    */
    mkPieRelease = pie.mkPieRelease;

    /**
      Runs `.phpt` tests ([PHP's test format](https://php.github.io/php-src/miscellaneous/writing-tests.html))
      with PHP's `run-tests.php`, as a check. It fails with the diff of each failing test, or
      if `src` has no `.phpt` files.

      # Inputs

      - `php`: The PHP to run the tests with.
      - `extensions`: Extensions to load, through `php.withExtensions`. Default: `[ ]`.
      - `src`: The directory with the `.phpt` files, in subdirectories too.
      - `flags`: More arguments for `run-tests.php`. Default: `[ ]`.
      - `name`: Default: `"php-tests"`.

      # Example

      ```nix
      checks.tests = rustPhpPlatform.runPhpTests {
        php = pkgs.php84;
        extensions = [ hello ];
        src = ./tests;
      };
      ```
    */
    runPhpTests = self.callPackage ./run-php-tests.nix { };

    /**
      Runs a FrankenPHP server and a test against it, as a check: an extension used the way
      FrankenPHP uses it, which `.phpt` tests with the CLI don't, with threads (ZTS), and in
      worker mode a script that stays loaded across requests (the request starts and ends
      differently: `RINIT` doesn't run for each request) and workers that restart.

      The server serves `src` on a free port on 127.0.0.1 (which the sandbox allows, on macOS
      too), in worker mode with `worker`, and the test is a bash script (`set -euo pipefail`)
      with:
      - `get <path> [curl arguments]`: prints the response's body, and fails with it on an HTTP
        error
      - `expect <path> <body>`: fails unless the response's body is `<body>`
      - `concurrently <n> <path>`: `<n>` requests at once, which must all succeed
      - `restart_workers`: restarts the workers (FrankenPHP's admin API), as
        `frankenphp run --watch` and `opcache_reset()` do: FrankenPHP shuts PHP down and starts
        it again in the same process, so every module's shutdown and startup (`MSHUTDOWN`,
        `MINIT`) run again, with the module still loaded
      - `$url` and `$admin_url`: the server's and its admin API's addresses

      The check fails if PHP warns when it starts (an extension that doesn't load), if the test
      fails, or if FrankenPHP exits during the test or doesn't exit cleanly afterwards, with
      FrankenPHP's log.

      # Inputs

      - `frankenphp`: The FrankenPHP to run, with the extensions to test. FrankenPHP embeds PHP
        with thread safety (ZTS), so they must be built for its PHP. nixpkgs' `frankenphp`
        rebuilds `php.withExtensions`'s for it (nixpkgs' and an
        [extension overlay](#ext-php-rslibmkphpextensionsoverlay)'s):
        `pkgs.frankenphp.override { php = pkgs.php.withExtensions ({ enabled, all }: enabled ++ [ all.hello ]); }`.
        Without an overlay, build the extension against `pkgs.frankenphp.php.unwrapped`. With
        nixpkgs' default PHP, FrankenPHP's PHP comes from nixpkgs' binary cache.
      - `src`: The document root.
      - `script`: The test.
      - `worker`: The worker script in `src`, or `null` for classic mode, where each request runs
        its script. Default: `"index.php"`.
      - `workers`: The number of workers. Default: `2`.
      - `threads`: PHP's threads, more than `workers`. Default: two more than the workers.
      - `name`: Default: `"frankenphp-tests"`.

      # Example

      ```nix
      checks.frankenphp = rustPhpPlatform.runFrankenphpTests {
        # With an extension overlay applied to pkgs.
        frankenphp = pkgs.frankenphp.override {
          php = pkgs.php.withExtensions ({ enabled, all }: enabled ++ [ all.hello ]);
        };
        # index.php: while (frankenphp_handle_request(fn () => print hello_world($_GET["name"]))) {}
        src = ./tests/frankenphp;
        script = ''
          expect "/?name=Nix" "Hello, Nix!"
          restart_workers
          expect "/?name=Nix" "Hello, Nix!"
          concurrently 20 "/?name=Nix"
        '';
      };
      ```
    */
    runFrankenphpTests = self.callPackage ./run-frankenphp-tests.nix { };

    /**
      Runs PHP-FPM, behind Caddy, and a test against it, as a check: an extension used the way
      FPM uses it, which `.phpt` tests with the CLI don't. FPM's master loads the extensions
      (`MINIT`) and then forks the children that handle requests. The threads an extension starts
      in `MINIT` (a Tokio runtime's, say) aren't in the children, every child shares the
      connections it opened, and each child shuts the module down (`MSHUTDOWN`) itself when it
      exits. Each child also handles many requests, one after another.

      FPM runs with `pm = static`: all `children` from the start, each exiting after
      `maxRequests` requests (`pm.max_requests`) if that isn't 0, when FPM forks another. Caddy
      serves `src` on a free port on 127.0.0.1 (which the sandbox allows, on macOS too), sending
      PHP scripts (and every path without a file, to `index.php`) to FPM, and the test is a bash
      script (`set -euo pipefail`) with:
      - `get`, `expect` and `concurrently`, as in
        [`runFrankenphpTests`](#rustphpplatformrunfrankenphptests)
      - `reload`: reloads FPM (`SIGUSR2`, as `systemctl reload php-fpm` does): the children exit,
        and the master runs itself again, loading the extensions again, and forks new children.
        It returns once they're ready.
      - `$url`: the server's address; `$fpm_pid` and `$fpm_log`: FPM's master and its log

      The check fails if PHP warns when it starts, in the CLI or FPM's master, and after a
      `reload` (an extension that doesn't load), if the test fails, if a child of FPM crashes (FPM starts another, so a request fails at most) or exits
      with an error, or if FPM exits during the test or doesn't stop cleanly afterwards, with
      FPM's, PHP's and Caddy's logs. FPM logs how a child exited only while it runs, not when it
      reloads or stops: set `maxRequests` to check the module's shutdown in the children.

      # Inputs

      - `php`: The PHP whose FPM runs.
      - `extensions`: Extensions to load, through `php.withExtensions`. Default: `[ ]`.
      - `src`: The document root.
      - `script`: The test.
      - `children`: The number of children (`pm.max_children`). Default: `2`.
      - `maxRequests`: The requests each child handles before it exits (`pm.max_requests`), or
        `0` for no limit. Default: `0`.
      - `settings`: More pool settings, such as `{ "php_admin_value[memory_limit]" = "256M"; }`.
        Default: `{ }`.
      - `name`: Default: `"fpm-tests"`.

      # Example

      ```nix
      checks.fpm = rustPhpPlatform.runFpmTests {
        php = pkgs.php84;
        extensions = [ hello ];
        # index.php: echo hello_world($_GET["name"]);
        src = ./tests/fpm;
        # Each child exits after 5 requests, and FPM forks another.
        maxRequests = 5;
        script = ''
          expect "/?name=Nix" "Hello, Nix!"
          concurrently 20 "/?name=Nix"
          reload
          expect "/?name=Nix" "Hello, Nix!"
        '';
      };
      ```
    */
    runFpmTests = self.callPackage ./run-fpm-tests.nix { };

    /**
      A command (`load-pie-archives`, not a check: it needs Docker) that loads a PIE release's
      Linux archives into PHP's official Docker images and runs `.phpt` tests there. Each archive
      goes into the image of its PHP version, thread safety, CPU and C library (`php:8.4-zts-alpine`
      for `…_php8.4-x86_64-linux-musl-zts.tgz`), and the tests run with the image's
      `run-tests.php`, with the module loaded alone (`php -n`). This tests the archives users
      install, in a PHP that isn't Nix's.

      ```
      load-pie-archives [--php <minor>] [--ts <nts|zts>] [--libc <glibc|musl>]
                        [--arch <x86_64|arm64>] <archives> <tests>
      ```

      - `<archives>`: A directory of PIE archives, such as [`mkPieRelease`](#rustphpplatformmkpierelease)'s.
      - `<tests>`: The `.phpt` tests: `<tests>/<extension>` if it exists (for archives of several
        extensions), otherwise `<tests>`.
      - The options select the archives. `--arch` is this machine's CPU by default; another
        needs emulation (Docker Desktop's, or QEMU's binfmt handlers).

      `DOCKER` is the command to run: `docker` by default, `podman` works too. PHP 8.6's NTS
      archives go into its `nts` images (`php:8.6-nts-alpine`); later PHPs' official images are
      ZTS only, so their NTS archives are skipped. It fails if an archive's tests fail,
      or if no archive is selected.

      # Example

      ```nix
      # nix build .#pie && nix run .#load-test -- --php 8.4 result tests
      packages.load-test = rustPhpPlatform.loadPieArchives;
      ```
    */
    loadPieArchives = self.callPackage ./load-pie-archives.nix { };

    /**
      `mkShell` for `cargo build` (and clippy, rust-analyzer, …) in an ext-php-rs project,
      against a PHP from nixpkgs: it has `php` and its `php-config`, which ext-php-rs's build
      script runs, and the libclang bindgen needs.

      A module built by `cargo build` on macOS needs `-undefined dynamic_lookup`. Put it in
      `.cargo/config.toml`, as the template does (`buildRustPhpExtension` sets it itself).

      # Inputs

      - `php`: The PHP to build against.
      - `toolchain`: The Rust toolchain, with the components wanted (rust-overlay's
        `.override { extensions = [ … ]; }`). Default: the scope's `rustToolchain`.

      Other arguments are `mkShell`'s.

      # Example

      ```nix
      devShells.default = rustPhpPlatform.mkShell { php = pkgs.php84; };
      ```
    */
    mkShell = self.callPackage ./mk-shell.nix { inherit mkShell; };

    /**
      The common targets, one per OS, CPU and C library:
      - `x86_64-linux-glibc`, `aarch64-linux-glibc`: glibc 2.28 or later
      - `x86_64-linux-musl`, `aarch64-linux-musl`
      - `x86_64-darwin`, `aarch64-darwin`: macOS 11.0 or later

      [`mkTarget`](#rustphpplatformmktarget) makes others.
    */
    targets = import ./targets.nix {
      inherit lib;
      inherit (self) mkTarget;
    };

    /**
      Makes a target, for another glibc floor or minimum macOS.

      PIE names archives by OS, CPU and C library only, so a release can have only one target
      of each: a custom target replaces the default one with the same OS, CPU and C library.

      # Inputs

      - `arch`: `"x86_64"` or `"aarch64"`.
      - `os`: `"linux"` or `"darwin"`. Default: `"linux"`.
      - `libc`: `"glibc"` or `"musl"` on Linux, `"bsdlibc"` on macOS. Default: `"glibc"` on Linux.
      - `glibc`: The oldest glibc the module loads on. Default: `"2.28"`.
      - `macos`: The oldest macOS the module loads on. Default: `"11.0"`.

      # Example

      ```nix
      targets = with rustPhpPlatform; [
        (mkTarget { arch = "x86_64"; glibc = "2.31"; })
        (mkTarget { arch = "aarch64"; os = "darwin"; macos = "13.0"; })
        targets.aarch64-linux-musl
      ];
      ```
    */
    mkTarget = import ./mk-target.nix { inherit lib; };

    /**
      Makes one PIE archive and its `.sha256` file, from an extension built with a `target`.
      [`mkPieRelease`](#rustphpplatformmkpierelease) uses it for each extension.
    */
    mkPieArchive = pie.mkPieArchive;

    /**
      The name PIE looks for an extension built with a `target` under:
      `php_<extensionName>-<version>_php<minor>-<arch>-<os>-<libc>-<nts|zts>.tgz`.
    */
    pieAssetName = pie.pieAssetName;

    /**
      The headers of a PHP version configured for a target (`./configure` only, nothing is
      compiled), with a `php-config` that runs on the build platform and a stub for `php -i`.
      Portable builds build against them: see [How a portable build works](portable-builds.md).

      # Inputs

      - `php`: The PHP whose source to configure.
      - `target`: The target to configure for.
      - `ztsSupport`: Whether to configure a thread-safe (ZTS) PHP, as nixpkgs' PHP's `ztsSupport`.
    */
    mkPhpHeaders = self.callPackage ./php-headers.nix { };

    /**
      The Rust toolchain (rustc and cargo) the scope builds with: the `rustToolchain` input, or
      nixpkgs' rustc and cargo.
    */
    rustToolchain =
      if rustToolchain != null then
        rustToolchain
      else
        symlinkJoin {
          name = "rust-toolchain-${rustc.version}";
          paths = [
            rustc
            cargo
          ];
          # Has the build platform's standard library only.
          passthru.nativeOnly = true;
        };

    /**
      A function from a target to a toolchain with its standard library, for portable builds.
      By default, it adds the target with `rustToolchain.override { targets = [ … ]; }` if the
      toolchain supports it (rust-overlay's do), and otherwise uses `rustToolchain` itself, which
      must then have it. nixpkgs' Rust can't add targets: rust-overlay's latest stable toolchain
      is used instead, if its overlay is applied.
    */
    rustToolchainFor =
      let
        addTarget = toolchain: target: toolchain.override { targets = [ target.rustTarget ]; };
      in
      target:
      if self.rustToolchain ? override && lib.functionArgs self.rustToolchain.override ? targets then
        addTarget self.rustToolchain target
      else if self.rustToolchain.nativeOnly or false then
        if rust-bin != null then
          addTarget rust-bin.stable.latest.minimal target
        else
          throw "ext-php-rs: building for ${target.name} needs a Rust toolchain with its standard library, not nixpkgs' rustc: apply rust-overlay's overlay (pkgs.rust-bin), or set rustToolchain to a rust-overlay toolchain or one with ${target.rustTarget}"
      else
        self.rustToolchain;

    /**
      The `rustPlatform` that native builds use (`buildRustPhpExtension` without a target):
      nixpkgs' for nixpkgs' Rust, otherwise `makeRustPlatform` with `rustToolchain`.
    */
    rustPlatform =
      # nixpkgs' own builds for the package set's host platform (pkgsCross) as well. Another
      # toolchain must run on the build platform and have the host's standard library, which
      # rustToolchainFor adds.
      if self.rustToolchain.nativeOnly or false then
        rustPlatform
      else
        let
          toolchain =
            if stdenv.buildPlatform == stdenv.hostPlatform then
              self.rustToolchain
            else
              self.rustToolchainFor {
                name = stdenv.hostPlatform.config;
                rustTarget = stdenv.hostPlatform.rust.rustcTarget;
              };
          # buildRustPackage reads the platforms rustc can build for.
          rustc = toolchain // {
            targetPlatforms = toolchain.targetPlatforms or lib.platforms.all;
            badTargetPlatforms = toolchain.badTargetPlatforms or [ ];
          };
        in
        makeRustPlatform {
          inherit rustc;
          cargo = toolchain;
        };

    # The zig that portable builds compile and link with (documented as an input above).
    inherit zig;

    /**
      The libclang bindgen uses in portable builds: that of the LLVM zig is built with, found
      among zig's build inputs. zig's builtin headers (`arm_neon.h`, …) only parse with the same
      clang version.
    */
    zigLibclang =
      let
        clang =
          lib.findFirst (input: lib.getName input == "clang")
            (throw "ext-php-rs: no clang among the build inputs of zig ${self.zig.version}: set zigLibclang (overrideScope) to the libclang of its LLVM")
            self.zig.buildInputs;
      in
      # zig's build inputs name one output (dev); libclang itself is in lib.
      clang.lib or clang;

    /**
      cargo-zigbuild with the scope's zig, at least 0.24, which macOS targets need. nixpkgs has
      0.23.4, so this builds 0.24.1 until nixpkgs catches up.
    */
    cargo-zigbuild =
      # 0.24 keeps rustc's -exported_symbols_list file with the flag for zig 0.16 and later
      # (every cdylib), and gives zig the minimum macOS (MACOSX_DEPLOYMENT_TARGET).
      let
        withZig = cargo-zigbuild.override { inherit (self) zig; };
      in
      if lib.versionAtLeast withZig.version "0.24" then
        withZig
      else
        withZig.overrideAttrs (
          finalAttrs: old: {
            version = "0.24.1";
            src = fetchFromGitHub {
              owner = "rust-cross";
              repo = "cargo-zigbuild";
              tag = "v${finalAttrs.version}";
              hash = "sha256-8kwrI0pPCfFoA9tEsle5X/BBtrHFcfw8cMvStHTYaz4=";
            };
            cargoHash = "sha256-pq09R4V0o99HvcnddaAkY4/0PUtMXL+BRg/nWvO+/GU=";
            # A test writes cargo-zigbuild's cache directory, in HOME.
            preCheck = (old.preCheck or "") + ''
              export HOME=$(mktemp -d)
            '';
          }
        );

    /**
      The macOS SDK that macOS targets build with, from any build platform: nixpkgs'
      `apple-sdk.src` (Apple's Command Line Tools SDK).
    */
    macosSdk = apple-sdk.src;
  }
)

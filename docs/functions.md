# Functions

<!-- Generated from the doc comments in lib/: run `update-docs` (devenv) after changing them. -->

The flake's [`lib`](#ext-php-rslib) output has the functions that need no package set, and
`makeRustPhpPlatform`, which makes the [`rustPhpPlatform`](#rustphpplatform) scope of
functions for a package set. The overlay adds that scope as `pkgs.rustPhpPlatform`, and the
devenv module as `config.ext-php-rs.lib`.

- `ext-php-rs.lib`
  - [`ext-php-rs.lib.makeRustPhpPlatform`](#ext-php-rslibmakerustphpplatform)
  - [`ext-php-rs.lib.targets`](#ext-php-rslibtargets)
  - [`ext-php-rs.lib.mkTarget`](#ext-php-rslibmktarget)
  - [`ext-php-rs.lib.extensionArgs`](#ext-php-rslibextensionargs)
  - [`ext-php-rs.lib.mkPhpExtensionsOverlay`](#ext-php-rslibmkphpextensionsoverlay)
- `rustPhpPlatform`
  - [`rustPhpPlatform.buildRustPhpExtension`](#rustphpplatformbuildrustphpextension)
  - [`rustPhpPlatform.extensionArgs`](#rustphpplatformextensionargs)
  - [`rustPhpPlatform.buildPieRelease`](#rustphpplatformbuildpierelease)
  - [`rustPhpPlatform.mkPieRelease`](#rustphpplatformmkpierelease)
  - [`rustPhpPlatform.runPhpTests`](#rustphpplatformrunphptests)
  - [`rustPhpPlatform.runFrankenphpTests`](#rustphpplatformrunfrankenphptests)
  - [`rustPhpPlatform.runFpmTests`](#rustphpplatformrunfpmtests)
  - [`rustPhpPlatform.loadPieArchives`](#rustphpplatformloadpiearchives)
  - [`rustPhpPlatform.mkShell`](#rustphpplatformmkshell)
  - [`rustPhpPlatform.targets`](#rustphpplatformtargets)
  - [`rustPhpPlatform.mkTarget`](#rustphpplatformmktarget)
  - [`rustPhpPlatform.mkPieArchive`](#rustphpplatformmkpiearchive)
  - [`rustPhpPlatform.pieAssetName`](#rustphpplatformpieassetname)
  - [`rustPhpPlatform.mkPhpHeaders`](#rustphpplatformmkphpheaders)
  - [`rustPhpPlatform.rustToolchain`](#rustphpplatformrusttoolchain)
  - [`rustPhpPlatform.rustToolchainFor`](#rustphpplatformrusttoolchainfor)
  - [`rustPhpPlatform.rustPlatform`](#rustphpplatformrustplatform)
  - [`rustPhpPlatform.zigLibclang`](#rustphpplatformziglibclang)
  - [`rustPhpPlatform.cargo-zigbuild`](#rustphpplatformcargo-zigbuild)
  - [`rustPhpPlatform.macosSdk`](#rustphpplatformmacossdk)

## `ext-php-rs.lib`
The flake's `lib` output: functions that don't need a package set, and `makeRustPhpPlatform`,
which makes the [`rustPhpPlatform` scope](#rustphpplatform) for one.

### `ext-php-rs.lib.makeRustPhpPlatform`

Makes the [`rustPhpPlatform` scope](#rustphpplatform) for a package set: the same as
`pkgs.callPackage ./lib { … }`.

#### Inputs

- `pkgs`: The package set to build with and for.
- `rustToolchain`: The Rust toolchain (rustc and cargo). Default: nixpkgs' rustc and cargo. Portable builds
  need each target's standard library: a rust-overlay toolchain gets it added
  automatically, any other toolchain must already have it.
- `zig`: The zig that portable builds compile and link with. Default: `pkgs.zig`. It must be a zig
  from nixpkgs, whose build inputs include the libclang of its LLVM.

#### Example

```nix
rustPhpPlatform = ext-php-rs.lib.makeRustPhpPlatform {
  inherit pkgs;
  rustToolchain = (rust-overlay.lib.mkRustBin { } pkgs).stable.latest.minimal;
};
```

### `ext-php-rs.lib.targets`

The common targets: the same as
[`rustPhpPlatform.targets`](#rustphpplatformtargets).

### `ext-php-rs.lib.mkTarget`

Makes a target: the same as [`rustPhpPlatform.mkTarget`](#rustphpplatformmktarget).

### `ext-php-rs.lib.extensionArgs`

Reads `buildRustPhpExtension`'s arguments from a project's files: the same as
[`rustPhpPlatform.extensionArgs`](#rustphpplatformextensionargs).

### `ext-php-rs.lib.mkPhpExtensionsOverlay`

Makes an overlay that adds extensions to every PHP of nixpkgs (`php`, `php84`, `php85`, …),
the way nixpkgs adds its own: to `php.extensions`. Each extension is built against the PHP
that loads it, and users load it like one of nixpkgs':
- `php.withExtensions ({ enabled, all }: enabled ++ [ all.<name> ])`
- devenv: `languages.php.extensions = [ "<name>" ];`

The overlay doesn't rebuild PHP, and several such overlays combine.

#### Inputs

- `extensions`: Either a list of `buildRustPhpExtension`'s arguments (without `php`), each added under
  its `extensionName`; or a function from `{ pkgs, php, rustPhpPlatform }` to an attribute
  set of extensions built against `php`.
- `rustPhpPlatform`: A function from the package set to the `rustPhpPlatform` to build with. Default:
  `pkgs.callPackage ./lib { }`, with nixpkgs' Rust.

#### Examples

```nix
overlays.default = ext-php-rs.lib.mkPhpExtensionsOverlay {
  extensions = [ (ext-php-rs.lib.extensionArgs { root = ./.; }) ];
};
```

```nix
overlays.default = ext-php-rs.lib.mkPhpExtensionsOverlay {
  extensions = { php, rustPhpPlatform, ... }: {
    hello = rustPhpPlatform.buildRustPhpExtension {
      pname = "hello";
      version = "0.1.0";
      src = ./.;
      cargoLock.lockFile = ./Cargo.lock;
      inherit php;
    };
  };
};
```


## `rustPhpPlatform`
The functions for one package set, and the tools they build with. Get it with
[`ext-php-rs.lib.makeRustPhpPlatform`](#ext-php-rslibmakerustphpplatform), from the overlay
(`pkgs.rustPhpPlatform`), or with `pkgs.callPackage ./lib { … }`.

It's a scope (`lib.makeScope`): change any of its attributes, such as `rustToolchain`,
with `rustPhpPlatform.overrideScope (final: prev: { … })`.

### Inputs

- `rustToolchain`: The Rust toolchain (rustc and cargo). Default: nixpkgs' rustc and cargo. Portable builds
  need each target's standard library: rust-overlay's toolchains get it added
  automatically, any other toolchain must already have it. With nixpkgs' Rust, portable
  builds use rust-overlay's latest stable toolchain if its overlay is applied (`pkgs.rust-bin`),
  and native builds keep nixpkgs' Rust.
- `zig`: The zig that portable builds compile and link with. Default: `pkgs.zig`.

### `rustPhpPlatform.buildRustPhpExtension`

Builds a PHP extension written in Rust with ext-php-rs. It extends the scope's
`rustPlatform.buildRustPackage`, and takes its arguments too.

- **Without a `target`**, it builds the way `buildRustPackage` does, for the package set's
  host platform and against `php`: a package for `php.withExtensions`. From
  `pkgsCross.<platform>.callPackage`, that's another Nix platform's PHP.
- **With a `target`**, it's a portable build: cross-compiled from any platform, it loads
  in any PHP of that target and thread safety, not only Nix's. See
  [How a portable build works](portable-builds.md).

The derivation is named `php-<pname>-<version>`, as nixpkgs names its PHP extensions.

#### Inputs

- `php`: The PHP to build against. With a `target`, only its version matters: the build uses
  that version's headers, configured for the target.
- `target`: For a portable build, a target from [`targets`](#rustphpplatformtargets) or
  [`mkTarget`](#rustphpplatformmktarget). This is a compile target for Cargo, not Nix's
  `targetPlatform`.
- `zts`: For a portable build, whether to build for a thread-safe (ZTS) PHP. Without a target,
  `php`'s own thread safety is used.
- `pname`, `version`, `src`: As for `buildRustPackage`.
- `cargoHash`, `cargoLock` or `cargoDeps`: The Cargo dependencies, as for `buildRustPackage`.
- `buildCargoArtifacts`: Whether to compile the Cargo dependencies in a derivation of
  their own, which a change to the source doesn't rebuild: only another PHP, target, thread
  safety, toolchain, profile, feature set or `Cargo.lock` does. Default: `false`. Enable it
  for builds that are repeated as the source changes. Each combination keeps its `target/`
  in the store, compressed (tens to hundreds of megabytes), and CI needs a binary cache to
  reuse it between jobs. The dependencies are built from the vendored crates in the store
  and from stubs of `src`: its Cargo manifests, `Cargo.lock` and `.cargo/`, with an empty
  file for each target and build script. So:
  - `src` must be a directory, not an archive to unpack, and is read during evaluation.
    One that is a derivation (`fetchFromGitHub`) is built then (import from derivation).
  - `patches` and hooks (`postPatch`, `preBuild`, …) that change other source files fail,
    as do hooks that patch the vendored crates and build scripts that write to them: the
    build reads them from the store (`cargoDeps`). Changes to the writable vendor copy,
    including executable-bit changes, are checked after pre-build hooks. Patch `cargoDeps`
    itself or use the default for those builds.
- `cargoPackage`: The Cargo package to build. Default: `pname`.
- `extensionName`: The PHP module's name, as `extension=` loads it. Default: `cargoPackage`.
- `libName`: The cdylib's name (`[lib] name` in `Cargo.toml`). Default: `cargoPackage`, with `-`
  replaced by `_`.
- `allowedLibraries`: For a portable build, the shared libraries the module may link to. Default: the
  target's C library (on macOS, the system's libraries and frameworks).

Other arguments are `buildRustPackage`'s: `buildType` (`"release"` or `"debug"`),
`buildFeatures`, `buildNoDefaultFeatures`, `buildAndTestSubdir`, `cargoBuildFlags`, …
Its tests are off (`doCheck = false`): a module's tests need PHP's embed SAPI.

#### Output

- `lib/php/extensions/<extensionName>.so`: the module.
- `share/ext-php-rs/bindings.rs`: the Zend API as bindgen generated it, to compare
  builds against other headers.
- `passthru`: `extensionName`, `phpVersion`, `zts`, `target` and `headers`. With
  `buildCargoArtifacts`, `cargoArtifacts` is the dependency derivation, e.g.
  `nix build .#hello.cargoArtifacts` to seed a binary cache.

The builds set the rustflags an ext-php-rs module needs (`-undefined dynamic_lookup` on
macOS, no static C library on musl), on top of a project's own `.cargo/config.toml`.

#### Install check

Without a target, the module is loaded into `php`. With one, the check reads the module:
it may only need the C library (on macOS, the system's libraries and frameworks), no glibc
symbol newer than the target's floor and no newer macOS than its minimum. It's also loaded
into `php` when `php` is of the target's platform (OS, CPU, C library and thread safety).

#### Examples

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
  zts = true;
};
```

### `rustPhpPlatform.extensionArgs`

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

#### Inputs

- `root`: The crate's directory, with its `Cargo.toml`.
- `workspace`: For a crate in a workspace, the workspace's directory: its `[workspace.package]`,
  `Cargo.lock` and `composer.json`. Default: `root`.
- `src`: The source to build, for another layout (files the code includes, a narrower
  workspace).

Any other argument is passed through, and overrides what is read.

#### Examples

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

### `rustPhpPlatform.buildPieRelease`

Builds a release of one extension for [PIE](https://github.com/php/pie): `args` built
for every combination of `php`, `targets` and `threadSafety`, as one
[`mkPieRelease`](#rustphpplatformmkpierelease).

#### Inputs

- `args`: `buildRustPhpExtension`'s arguments, without `php`, `target` and `zts`.
- `php`: The PHPs to build for (a list): one archive per PHP minor.
- `targets`: The targets to build for. Default: every one of [`targets`](#rustphpplatformtargets).
- `threadSafety`: Default: `[ "nts" "zts" ]`.
- `name`: The derivation's name. Default: `mkPieRelease`'s.

#### Example

```nix
# Every target, NTS and ZTS, for PHP 8.4 and 8.5: 24 archives.
pie = rustPhpPlatform.buildPieRelease {
  args = ext-php-rs.lib.extensionArgs { root = ./.; };
  php = [ pkgs.php84 pkgs.php85 ];
};
```

### `rustPhpPlatform.mkPieRelease`

Collects portable builds into a release for [PIE](https://github.com/php/pie): a
directory with one archive per extension, each with its `.sha256` file, and `SHA256SUMS`.
The archives are named the way `pie install` looks for them among a GitHub release's
assets, such as `php_hello-0.1.0_php8.4-arm64-linux-musl-zts.tgz`.

`passthru.archives` has each archive's derivation.

#### Inputs

- `extensions`: Extensions built with a `target`. Each combination of PHP minor, target and thread
  safety may appear only once.
- `name`: The derivation's name. Default: `php-<pname>-<version>-pie`, which needs every
  extension to be of the same package and version.

#### Example

```nix
pie = rustPhpPlatform.mkPieRelease { extensions = [ hello-musl hello-darwin ]; };
```

### `rustPhpPlatform.runPhpTests`

Runs `.phpt` tests ([PHP's test format](https://php.github.io/php-src/miscellaneous/writing-tests.html))
with PHP's `run-tests.php`, as a check. It fails with the diff of each failing test, or
if `src` has no `.phpt` files.

#### Inputs

- `php`: The PHP to run the tests with.
- `extensions`: Extensions to load, through `php.withExtensions`. Default: `[ ]`.
- `src`: The directory with the `.phpt` files, in subdirectories too.
- `flags`: More arguments for `run-tests.php`. Default: `[ ]`.
- `name`: Default: `"php-tests"`.

#### Example

```nix
checks.tests = rustPhpPlatform.runPhpTests {
  php = pkgs.php84;
  extensions = [ hello ];
  src = ./tests;
};
```

### `rustPhpPlatform.runFrankenphpTests`

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

#### Inputs

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

#### Example

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

### `rustPhpPlatform.runFpmTests`

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

#### Inputs

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

#### Example

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

### `rustPhpPlatform.loadPieArchives`

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

`DOCKER` is the command to run: `docker` by default, `podman` works too. PHP 8.6's official
images are ZTS only, so its NTS archives are skipped. It fails if an archive's tests fail,
or if no archive is selected.

#### Example

```nix
# nix build .#pie && nix run .#load-test -- --php 8.4 result tests
packages.load-test = rustPhpPlatform.loadPieArchives;
```

### `rustPhpPlatform.mkShell`

`mkShell` for `cargo build` (and clippy, rust-analyzer, …) in an ext-php-rs project,
against a PHP from nixpkgs: it has `php` and its `php-config`, which ext-php-rs's build
script runs, and the libclang bindgen needs.

A module built by `cargo build` on macOS needs `-undefined dynamic_lookup`. Put it in
`.cargo/config.toml`, as the template does (`buildRustPhpExtension` sets it itself).

#### Inputs

- `php`: The PHP to build against.
- `toolchain`: The Rust toolchain, with the components wanted (rust-overlay's
  `.override { extensions = [ … ]; }`). Default: the scope's `rustToolchain`.

Other arguments are `mkShell`'s.

#### Example

```nix
devShells.default = rustPhpPlatform.mkShell { php = pkgs.php84; };
```

### `rustPhpPlatform.targets`

The common targets, one per OS, CPU and C library:
- `x86_64-linux-glibc`, `aarch64-linux-glibc`: glibc 2.28 or later
- `x86_64-linux-musl`, `aarch64-linux-musl`
- `x86_64-darwin`, `aarch64-darwin`: macOS 11.0 or later

[`mkTarget`](#rustphpplatformmktarget) makes others.

### `rustPhpPlatform.mkTarget`

Makes a target, for another glibc floor or minimum macOS.

PIE names archives by OS, CPU and C library only, so a release can have only one target
of each: a custom target replaces the default one with the same OS, CPU and C library.

#### Inputs

- `arch`: `"x86_64"` or `"aarch64"`.
- `os`: `"linux"` or `"darwin"`. Default: `"linux"`.
- `libc`: `"glibc"` or `"musl"` on Linux, `"bsdlibc"` on macOS. Default: `"glibc"` on Linux.
- `glibc`: The oldest glibc the module loads on. Default: `"2.28"`.
- `macos`: The oldest macOS the module loads on. Default: `"11.0"`.

#### Example

```nix
targets = with rustPhpPlatform; [
  (mkTarget { arch = "x86_64"; glibc = "2.31"; })
  (mkTarget { arch = "aarch64"; os = "darwin"; macos = "13.0"; })
  targets.aarch64-linux-musl
];
```

### `rustPhpPlatform.mkPieArchive`

Makes one PIE archive and its `.sha256` file, from an extension built with a `target`.
[`mkPieRelease`](#rustphpplatformmkpierelease) uses it for each extension.

### `rustPhpPlatform.pieAssetName`

The name PIE looks for an extension built with a `target` under:
`php_<extensionName>-<version>_php<minor>-<arch>-<os>-<libc>-<nts|zts>.tgz`.

### `rustPhpPlatform.mkPhpHeaders`

The headers of a PHP version configured for a target (`./configure` only, nothing is
compiled), with a `php-config` that runs on the build platform and a stub for `php -i`.
Portable builds build against them: see [How a portable build works](portable-builds.md).

#### Inputs

- `php`: The PHP whose source to configure.
- `target`: The target to configure for.
- `zts`: Whether to configure a thread-safe PHP.

### `rustPhpPlatform.rustToolchain`

The Rust toolchain (rustc and cargo) the scope builds with: the `rustToolchain` input, or
nixpkgs' rustc and cargo.

### `rustPhpPlatform.rustToolchainFor`

A function from a target to a toolchain with its standard library, for portable builds.
By default, it adds the target with `rustToolchain.override { targets = [ … ]; }` if the
toolchain supports it (rust-overlay's do), and otherwise uses `rustToolchain` itself, which
must then have it. nixpkgs' Rust can't add targets: rust-overlay's latest stable toolchain
is used instead, if its overlay is applied.

### `rustPhpPlatform.rustPlatform`

The `rustPlatform` that native builds use (`buildRustPhpExtension` without a target):
nixpkgs' for nixpkgs' Rust, otherwise `makeRustPlatform` with `rustToolchain`.

### `rustPhpPlatform.zigLibclang`

The libclang bindgen uses in portable builds: that of the LLVM zig is built with, found
among zig's build inputs. zig's builtin headers (`arm_neon.h`, …) only parse with the same
clang version.

### `rustPhpPlatform.cargo-zigbuild`

cargo-zigbuild with the scope's zig, at least 0.24, which macOS targets need. nixpkgs has
0.23.4, so this builds 0.24.1 until nixpkgs catches up.

### `rustPhpPlatform.macosSdk`

The macOS SDK that macOS targets build with, from any build platform: nixpkgs'
`apple-sdk.src` (Apple's Command Line Tools SDK).



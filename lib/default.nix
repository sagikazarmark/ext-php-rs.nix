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
      - `zts`: For a portable build, whether to build for a thread-safe (ZTS) PHP. Without a target,
        `php`'s own thread safety is used.
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
      - `passthru`: `extensionName`, `phpVersion`, `zts`, `target` and `headers`.

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
        zts = true;
      };
      ```
    */
    buildRustPhpExtension = self.callPackage ./build-extension { };

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

      - `args`: `buildRustPhpExtension`'s arguments, without `php`, `target` and `zts`.
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
      - `zts`: Whether to configure a thread-safe PHP.
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

# Build PHP extensions written in Rust with ext-php-rs (https://github.com/extphprs/ext-php-rs):
# for a PHP from nixpkgs, and cross-compiled for any Linux or macOS as PIE's prebuilt binaries.
#
#   rustPhpPlatform = pkgs.callPackage ./. { rustToolchain = …; };
#
#   # Loaded by this PHP: php.withExtensions ({ enabled, ... }: enabled ++ [ ext ]). This is
#   # buildRustPackage for the package set's host platform: from pkgsCross.<platform>.callPackage,
#   # for that platform's PHP.
#   ext = rustPhpPlatform.buildRustPhpExtension { pname; version; src; cargoLock.lockFile; php = pkgs.php84; };
#
#   # For Linux on arm64 with musl, ZTS, built on any platform (or macOS: targets.aarch64-darwin).
#   ext = rustPhpPlatform.buildRustPhpExtension { …; php = pkgs.php84; target = rustPhpPlatform.targets.aarch64-linux-musl; zts = true; };
#
#   # Every archive PIE can download, in one directory: from built extensions, or built for
#   # every PHP, target and thread safety.
#   rustPhpPlatform.mkPieRelease { extensions = [ … ]; }
#   rustPhpPlatform.buildPieRelease { args = { pname; version; src; cargoLock.lockFile; }; php = [ pkgs.php84 pkgs.php85 ]; }
#
#   # The arguments from the project's Cargo.toml and composer.json; its .phpt tests; a shell
#   # for cargo.
#   args = rustPhpPlatform.extensionArgs { root = ./.; };
#   rustPhpPlatform.runPhpTests { php = pkgs.php84; extensions = [ ext ]; src = ./tests; }
#   rustPhpPlatform.mkShell { php = pkgs.php84; }
#
# rustToolchain is the Rust toolchain (rustc and cargo), by default nixpkgs'. Portable builds add
# their target's standard library with rustToolchain.override { targets = [ … ]; } where the
# toolchain supports it (rust-overlay's); any other toolchain must already have it, or set
# rustToolchainFor to a function from a target to a toolchain that has it. With nixpkgs' Rust,
# portable builds use rust-overlay's latest stable toolchain where its overlay is applied
# (pkgs.rust-bin), and native builds keep nixpkgs' Rust.
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

lib.makeScope newScope (self: {
  inherit zig;

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

  # A toolchain with the target's standard library: added with .override { targets } where the
  # toolchain has it (rust-overlay's), otherwise rustToolchain itself, which must then have it
  # (devenv's languages.rust.targets, for instance). nixpkgs' Rust has none: rust-overlay's
  # latest stable one instead, where its overlay is applied.
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

  # buildRustPackage's platform for rustToolchain: nixpkgs' own for nixpkgs' Rust, which
  # builds for the package set's host platform (pkgsCross) as well. Another toolchain must run
  # on the build platform and have the host's standard library, which rustToolchainFor adds.
  rustPlatform =
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

  # The macOS SDK that macOS targets build with, from any build platform: nixpkgs' (Apple's
  # Command Line Tools SDK, as Apple ships it).
  macosSdk = apple-sdk.src;

  # cargo-zigbuild with this zig on its PATH, at least 0.24, which macOS targets need: it keeps
  # rustc's -exported_symbols_list file with the flag for zig 0.16 and later (every cdylib), and
  # gives zig the minimum macOS (MACOSX_DEPLOYMENT_TARGET). nixpkgs has 0.23.4.
  cargo-zigbuild =
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

  # The libclang of the LLVM zig is built with: bindgen must be the same major version as the
  # builtin headers (arm_neon.h, …) zig ships, or it fails to parse them.
  zigLibclang =
    let
      clang =
        lib.findFirst (input: lib.getName input == "clang")
          (throw "ext-php-rs: no clang among the build inputs of zig ${self.zig.version}: set zigLibclang (overrideScope) to the libclang of its LLVM")
          self.zig.buildInputs;
    in
    # zig's build inputs name one output (dev); libclang itself is in lib.
    clang.lib or clang;

  mkTarget = import ./mk-target.nix { inherit lib; };

  targets = import ./targets.nix {
    inherit lib;
    inherit (self) mkTarget;
  };

  mkPhpHeaders = self.callPackage ./php-headers.nix { };

  buildRustPhpExtension = self.callPackage ./build-extension { };

  # buildRustPhpExtension's arguments read from a project's Cargo.toml and composer.json.
  extensionArgs = import ./extension-args.nix { inherit lib; };

  # .phpt tests run with PHP's run-tests.php.
  runPhpTests = self.callPackage ./run-php-tests.nix { };

  # A shell for cargo in an ext-php-rs project, with the scope's toolchain.
  mkShell = self.callPackage ./mk-shell.nix { inherit mkShell; };

  inherit (self.callPackage ./pie.nix { })
    pieAssetName
    mkPieArchive
    mkPieRelease
    buildPieRelease
    ;
})

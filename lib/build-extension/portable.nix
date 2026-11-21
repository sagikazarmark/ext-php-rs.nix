# buildRustPhpExtension with a target (targets.nix): a portable module for any Linux or macOS of that
# kind, not only Nix's, cross-compiled with cargo-zigbuild from any build platform against the
# headers of `php`'s version configured for the target (php-headers.nix), linked against the
# target's glibc floor, musl or minimum macOS (with nixpkgs' macOS SDK). The install check reads
# the module: it may need only the C library (on macOS, the system's libraries and frameworks),
# no glibc symbol newer than the floor and no newer macOS than the minimum. Where `php` is a PHP
# of that platform, it loads it too.
#
# Returns what sets this build apart from one for nixpkgs (nixpkgs.nix); default.nix does the
# rest.
{
  lib,
  stdenv,
  writeShellScriptBin,
  llvm,
  rustToolchainFor,
  cargo-zigbuild,
  zigLibclang,
  macosSdk,
  mkPhpHeaders,
}:

let
  # ext-php-rs's build script asks xcrun for the macOS SDK whenever it runs on macOS, and
  # passes it to bindgen even for a Linux target. Without an xcrun it uses none.
  xcrunStub = writeShellScriptBin "xcrun" "exit 1";

  # Shared libraries a module may need on each C library: PIE installs the module alone.
  defaultAllowedLibraries = {
    glibc = [
      "libc.so.6"
      "libm.so.6"
      "libpthread.so.0"
      "libdl.so.2"
      "ld-linux-*.so.*"
    ];
    # zig links musl as libc.so, which musl's loader resolves to itself.
    musl = [ "libc.so" ];
    # The system's libraries and frameworks, which every macOS has: not Nix's or Homebrew's.
    bsdlibc = [
      "/usr/lib/*"
      "/System/Library/Frameworks/*"
    ];
  };
in

{
  # The PHP version to configure for the target.
  php,
  target,
  # Thread safety.
  zts,
  extensionName,
  # The installed module's path.
  module,
  allowedLibraries,
  ...
}:

assert lib.assertMsg (lib.isBool zts) "buildRustPhpExtension: a target needs zts = true or false";

let
  darwin = target.os == "darwin";
  # The toolchain with the target's standard library. buildRustPackage puts the scope's own
  # cargo and rustc on PATH as well, which may not have it.
  toolchain = rustToolchainFor target;
  allowed =
    if allowedLibraries != null then allowedLibraries else defaultAllowedLibraries.${target.libc};
  phpZts = (php.unwrapped or php).ztsSupport or false;
  headers = mkPhpHeaders { inherit php target zts; };
  buildRust = stdenv.buildPlatform.rust;
in
{
  inherit headers zts darwin;

  inherit (target) rustTarget sharedLibrary;
  cargoTripleDir = target.rustTarget;
  # A cdylib cannot link the C library statically.
  rustflags = lib.optionals (target.libc == "musl") [
    "-C"
    "target-feature=-crt-static"
  ];

  nativeBuildInputs = [
    cargo-zigbuild
  ]
  ++ lib.optional stdenv.buildPlatform.isDarwin xcrunStub;

  # The toolchain first on PATH, whatever the order of the inputs: cargo zigbuild runs the
  # `cargo` it finds there, and Cargo the RUSTC it is given.
  preBuild = ''
    export PATH="${toolchain}/bin:$PATH" RUSTC="${toolchain}/bin/rustc"
  '';

  env = {
    # A stub for the target's PHP, which cannot run here.
    PHP = "${headers}/bin/php";
    PHP_CONFIG = "${headers}/bin/php-config";
    # bindgen parses the target's headers with zig's builtin headers (cargo-zigbuild adds
    # them), which only the libclang of zig's own LLVM version understands.
    LIBCLANG_PATH = "${zigLibclang}/lib";
  }
  # Build scripts and proc macros are linked for the build platform, by the linker a package's
  # .cargo/config.toml may name for its triple (kcs/mjml names aarch64-linux-gnu-gcc for
  # aarch64 glibc), which cargo-zigbuild only replaces for the target: the build platform's own
  # C compiler instead.
  // lib.optionalAttrs (buildRust.rustcTarget != target.rustTarget) {
    "CARGO_TARGET_${buildRust.cargoEnvVarTarget}_LINKER" = "${stdenv.cc}/bin/cc";
  };

  # Each one unless the package sets it.
  defaults = {
    # cargo zigbuild runs the toolchain's cargo, not the auditable one.
    auditable = false;

    # buildRustPackage's cargoBuildHook (pkgs/build-support/rust/hooks/cargo-build-hook.sh),
    # with cargo zigbuild for the target, and the same handling of buildAndTestSubdir,
    # buildType, buildNoDefaultFeatures, buildFeatures and cargoBuildFlags (the build-options
    # check builds with each). On purpose, it does not set CARGO_PROFILE_<profile>_STRIP=false
    # (the hook leaves stripping to stdenv, which does not strip here) or the hook's C compiler
    # variables for the host platform (zig is the C compiler).
    buildPhase = ''
      runHook preBuild
      # cargo-zigbuild keeps its linker wrappers in the user's cache directory.
      export HOME=$TMPDIR ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache
      ${lib.optionalString darwin ''
        # The same SDK on any build platform, for cargo-zigbuild to give zig and bindgen, and
        # the minimum macOS (instead of the build platform's, on macOS).
        export SDKROOT=${macosSdk} MACOSX_DEPLOYMENT_TARGET=${target.macos}
      ''}
      if [ -n "''${buildAndTestSubdir-}" ]; then
        export CARGO_TARGET_DIR="$(pwd)/target"
        pushd "$buildAndTestSubdir"
      fi
      extPhpRsFlags=(-j "$NIX_BUILD_CORES" --target ${target.cargoTarget} --offline)
      if [ "$cargoBuildType" != debug ]; then
        extPhpRsFlags+=(--profile "$cargoBuildType")
      fi
      if [ -n "''${cargoBuildNoDefaultFeatures-}" ]; then
        extPhpRsFlags+=(--no-default-features)
      fi
      if [ -n "''${cargoBuildFeatures-}" ]; then
        extPhpRsFlags+=("--features=$(concatStringsSep "," cargoBuildFeatures)")
      fi
      concatTo extPhpRsFlags cargoBuildFlags
      echoCmd 'cargo zigbuild flags' "''${extPhpRsFlags[@]}"
      cargo zigbuild "''${extPhpRsFlags[@]}"
      if [ -n "''${buildAndTestSubdir-}" ]; then
        popd
      fi
      runHook postBuild
    '';

    # Linked for another platform: keep the binary as the linker made it.
    dontStrip = true;
    dontPatchELF = true;
  };

  nativeInstallCheckInputs = [ llvm ];
  # The shared libraries the module needs, its glibc floor or minimum macOS.
  installCheck =
    (
      if darwin then
        ''
          needed=$(llvm-objdump --macho --dylibs-used ${module} | tail -n +2 \
            | sed 's/^[[:space:]]*//; s/ (compatibility version.*//' | grep -vx '${extensionName}.so' || true)
        ''
      else
        ''
          needed=$(llvm-readelf --dynamic-table ${module} | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
        ''
    )
    + ''
      echo "${extensionName}.so needs:" $needed
      for library in $needed; do
        case "$library" in
          ${lib.concatStringsSep "|" allowed}) ;;
          *) echo "${extensionName}.so needs $library, which is not one of: ${toString allowed}" >&2; exit 1 ;;
        esac
      done
    ''
    + lib.optionalString (target.glibc != null) ''
      newest=$(llvm-objdump --dynamic-syms ${module} | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -uV | tail -n 1)
      echo "newest glibc symbol version: $newest (floor ${target.glibc})"
      if [ "$(printf '%s\n%s\n' "$newest" ${target.glibc} | sort -V | tail -n 1)" != ${target.glibc} ]; then
        echo "${extensionName}.so needs glibc $newest, newer than ${target.glibc}" >&2
        exit 1
      fi
    ''
    + lib.optionalString darwin ''
      minos=$(llvm-objdump --macho --private-headers ${module} \
        | awk '/cmd LC_BUILD_VERSION/ { build = 1 } build && $1 == "minos" && !minos { minos = $2 } END { print minos }')
      echo "minimum macOS: $minos (${target.macos})"
      if [ "$(printf '%s\n%s\n' "$minos" ${target.macos} | sort -V | tail -n 1)" != ${target.macos} ]; then
        echo "${extensionName}.so needs macOS $minos, newer than ${target.macos}" >&2
        exit 1
      fi
    '';
  # Where `php` is a PHP of the target's platform: same OS, CPU, C library and thread safety.
  canLoadIntoPhp =
    stdenv.buildPlatform.canExecute stdenv.hostPlatform
    && target.system == stdenv.hostPlatform.system
    && (darwin || (target.libc == "musl") == stdenv.hostPlatform.isMusl)
    && zts == phpZts;
}

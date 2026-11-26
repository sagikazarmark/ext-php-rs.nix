{
  lib,
  callPackage,
  writeShellScript,
  buildPackages,
}:
{
  finalAttrs,
  preBuild,
  portable,
  buildPhase,
  customBuildPhase,
}:
let
  dummySrc = callPackage ./dummy-src.nix { } finalAttrs.src;
  # By its path, not on PATH: ext-php-rs's build script tracks PATH, and a zstd among
  # the inputs is one zstd-sys may link.
  zstd = lib.getExe buildPackages.zstd;
  # Cargo fingerprints RUSTFLAGS as strings. Expand the variable after Cargo has
  # computed them, without losing the path remap in the resulting binary.
  # The stubs of the dependency build are compiled without lints: an empty crate trips
  # some a project may deny or forbid ([lints]), and no attribute lifts a forbidden one.
  # Cargo caps the lints of the vendored crates itself.
  wrapper = writeShellScript "ext-php-rs-rustc" ''
    if [[ -n ''${EXT_PHP_RS_RUSTC_WRAPPER:-} ]]; then set -- "$EXT_PHP_RS_RUSTC_WRAPPER" "$@"; fi
    if [[ -n ''${EXT_PHP_RS_DUMMY_BUILD:-} && " $* " != *" --cap-lints"* ]]; then set -- "$@" --cap-lints allow; fi
    exec "$@" "--remap-path-prefix=$NIX_BUILD_TOP=/build" "--remap-path-prefix=$cargoDeps=/build/cargo-vendor-dir"
  '';
  selectVendor = ''
    # nixpkgs' cargoSetupHook uses a writable vendor copy in the build directory.
    # Keep its source replacement and linker config, but resolve vendored crates
    # at the same immutable path in both builds, including outside a Linux sandbox.
    if [[ ! -d "$cargoDeps" ]]; then
      echo 'buildCargoArtifacts requires a vendored Cargo directory' >&2
      exit 1
    fi
    # A hook that patched the copy would otherwise be ignored, without a word.
    extPhpRsCheckVendor
    # importCargoLock configures one relative directory; fetchCargoVendor can
    # configure many registries/git sources below the absolute vendor copy.
    substituteInPlace "$NIX_BUILD_TOP/.cargo/config.toml" \
      --replace-quiet 'directory = "cargo-vendor-dir"' "directory = \"$cargoDeps\"" \
      --replace-quiet "$NIX_BUILD_TOP/$(stripHash "$cargoDeps")" "$cargoDeps"
    # Otherwise the dependencies are compiled again wherever the build directory's name
    # changes, without a word.
    if ! grep -qF "$cargoDeps" "$NIX_BUILD_TOP/.cargo/config.toml"; then
      echo "buildCargoArtifacts: Cargo's configuration doesn't name the vendor directory the way cargoSetupHook writes it:" >&2
      cat "$NIX_BUILD_TOP/.cargo/config.toml" >&2
      exit 1
    fi
  '';
  # Register at build-phase entry, after setup/patch/configure hooks have had a
  # chance to register preBuildHooks. runHook snapshots that array *before* it
  # calls the package's preBuild, so registering inside preBuild is too late.
  checkedBuildPhase = ''
    extPhpRsCheckVendor() {
      if ! ${lib.getExe buildPackages.python3} ${./check-vendor.py} "$cargoDeps" "$NIX_BUILD_TOP/$(stripHash "$cargoDeps")"; then
        echo 'buildCargoArtifacts: a hook changed the vendored crates in the build directory, but this build reads them from the store (cargoDeps). Patch cargoDeps itself, or build without buildCargoArtifacts.' >&2
        exit 1
      fi
    }
    extPhpRsSelectVendor() {
      ${selectVendor}
    }
    preBuildHooks+=(extPhpRsSelectVendor)
  ''
  + buildPhase
  + lib.optionalString customBuildPhase ''

    # A custom buildPhase can add hooks of its own or change the vendor copy
    # after preBuild. Don't accept artifacts from an ignored patch in that case.
    extPhpRsCheckVendor
  '';
  preBuild' =
    preBuild
    + "\n"
    + ''
      export EXT_PHP_RS_RUSTC_WRAPPER="''${RUSTC_WRAPPER:-}" RUSTC_WRAPPER=${wrapper} CARGO_INCREMENTAL=0
    '';
  # Inherit the resolved build inputs, hooks, environment, features, profile and
  # actual buildPhase (cargoBuildHook or cargo zigbuild) from the module.
  artifacts = finalAttrs.finalPackage.overrideAttrs (_: {
    name = "${finalAttrs.name}-cargo-artifacts";
    src = dummySrc;
    cargoDeps = finalAttrs.cargoDeps;
    preBuild =
      preBuild'
      + ''
        export EXT_PHP_RS_DUMMY_BUILD=1
      ''
      + lib.optionalString portable ''
        export CARGO_ZIGBUILD_CACHE_DIR="$out/zigbuild"
      '';
    # Keep check inputs on PATH exactly as for the module: ext-php-rs's
    # build script explicitly tracks PATH. Only skip the checks themselves.
    checkPhase = ":";
    installCheckPhase = ":";
    dontFixup = true;
    # Compressed: a target/ is hundreds of megabytes, for each PHP, target and thread
    # safety. Every file gets the timestamp the store gives the sources, so Cargo takes
    # none of them for changed. Nix can't see the store paths in the archive: the module's
    # build has them as inputs of its own. Cargo records the build directory in it, so
    # where its name is random (outside a Linux sandbox) two builds of it differ.
    installPhase = ''
      mkdir -p "$out"
      tar --create --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner target \
        | ${zstd} -T"$NIX_BUILD_CORES" -3 -q -o "$out/target.tar.zst"
    '';
    passthru = { };
  });
in
{
  inherit artifacts dummySrc;
  buildPhase = checkedBuildPhase;
  preBuild =
    preBuild'
    + ''
      unset EXT_PHP_RS_DUMMY_BUILD
      ${zstd} -T"$NIX_BUILD_CORES" -d -q -c ${artifacts}/target.tar.zst | tar --extract
    ''
    + lib.optionalString portable ''
      export CARGO_ZIGBUILD_CACHE_DIR=${artifacts}/zigbuild
    '';
}

# Builds a PHP extension written in Rust with ext-php-rs: the Cargo package's cdylib,
# installed as lib/php/extensions/<extensionName>.so with `extensionName` set, which is
# what nixpkgs' `php.withExtensions` / `php.buildEnv` expect. It extends the scope's
# rustPlatform.buildRustPackage and takes its arguments (cargoHash or cargoLock, buildType,
# buildFeatures, buildNoDefaultFeatures, buildAndTestSubdir, cargoBuildFlags, …).
#
# Without a target, a package of the package set (nixpkgs.nix); with a target (targets.nix), a
# portable module for any Linux or macOS of that kind (portable.nix). Each returns what sets its build
# apart; the rest is the same for both, here.
#
# What a build returns:
#   headers, zts                 the PHP headers built against, and their thread safety
#   darwin, rustTarget,          the platform the module is for: macOS or not, its rustc
#   cargoTripleDir,              target, Cargo's directory under target/, and the cdylib's
#   sharedLibrary                file extension
#   nativeBuildInputs, env       joined with the package's own
#   canLoadIntoPhp               whether the install check loads the module into `php`
# and optionally (empty by default):
#   rustflags                    rustflags the module needs on that platform
#   preBuild                     runs before the rustflags are set, and the package's preBuild
#   defaults                     derivation arguments, each one unless the package sets it
#   installCheck, nativeInstallCheckInputs
#                                checks of the module before it is loaded
{
  lib,
  callPackage,
  rustPlatform,
}:

let
  forNixpkgs = callPackage ./nixpkgs.nix { };
  forPortable = callPackage ./portable.nix { };
in
lib.extendMkDerivation {
  constructDrv = rustPlatform.buildRustPackage;

  excludeDrvArgNames = [
    "php"
    "target"
    "zts"
    "cargoPackage"
    "libName"
    "allowedLibraries"
  ];

  extendDrvArgs =
    finalAttrs:
    {
      # The PHP to build against: without a target, the one that loads the module; with a
      # target, the PHP version to configure for it.
      php,
      target ? null,
      # Thread safety, for a target only (otherwise `php`'s own).
      zts ? null,
      cargoPackage ? finalAttrs.pname,
      # The PHP module name, as `extension=` loads it.
      extensionName ? cargoPackage,
      # The cdylib's name ([lib] name in Cargo.toml).
      libName ? lib.replaceStrings [ "-" ] [ "_" ] cargoPackage,
      buildType ? "release",
      cargoBuildFlags ? [ ],
      # Shared libraries the module may need, for a target only: by default its C library's.
      allowedLibraries ? null,
      nativeBuildInputs ? [ ],
      nativeInstallCheckInputs ? [ ],
      passthru ? { },
      ...
    }@args:
    let
      module = "$out/lib/php/extensions/${extensionName}.so";
      build = (if target == null then forNixpkgs else forPortable) {
        inherit
          php
          target
          zts
          extensionName
          module
          allowedLibraries
          ;
      };
      profileDir =
        if
          lib.elem buildType [
            "debug"
            "dev"
          ]
        then
          "debug"
        else
          buildType;
      outDir = "target/${build.cargoTripleDir}/${profileDir}";
      libFile = "lib${libName}${build.sharedLibrary}";
      rustflags = [
        # Panic locations name the source files; the build directory's name is random on macOS.
        "--remap-path-prefix=$NIX_BUILD_TOP=/build"
      ]
      ++ lib.optionals build.darwin [
        # A module leaves the Zend API's symbols to PHP, which defines them when it loads it.
        "-C"
        "link-arg=-undefined"
        "-C"
        "link-arg=dynamic_lookup"
        # Its name, instead of the path of the build.
        "-C"
        "link-arg=-Wl,-install_name,${extensionName}.so"
      ]
      ++ build.rustflags or [ ];
    in
    # The build's defaults (buildPhase, …), where the package sets none.
    lib.mapAttrs (name: value: args.${name} or value) (build.defaults or { })
    // {
      nativeBuildInputs = build.nativeBuildInputs ++ nativeBuildInputs;

      cargoBuildFlags = [
        "--package"
        cargoPackage
      ]
      ++ cargoBuildFlags;

      env = build.env // args.env or { };

      # The target's rustflags, given to Cargo with --config: they join the project's own
      # (.cargo/config.toml), which RUSTFLAGS would replace. Where RUSTFLAGS is set (by
      # buildRustPackage for a debug build on macOS, for one), they join it instead.
      preBuild =
        build.preBuild or ""
        + ''
          extPhpRsRustflags=(${lib.concatMapStringsSep " " (flag: ''"${flag}"'') rustflags})
          if [ -n "''${RUSTFLAGS-}" ]; then
            export RUSTFLAGS="$RUSTFLAGS ''${extPhpRsRustflags[*]}"
          else
            extPhpRsConfig=$(printf '"%s",' "''${extPhpRsRustflags[@]}")
            extPhpRsConfig="--config=target.${build.rustTarget}.rustflags=[''${extPhpRsConfig%,}]"
            if [[ "$(declare -p cargoBuildFlags 2>/dev/null)" == "declare -a"* ]]; then
              cargoBuildFlags+=("$extPhpRsConfig")
            else
              cargoBuildFlags="''${cargoBuildFlags-} $extPhpRsConfig"
            fi
          fi
        ''
        + args.preBuild or "";

      installPhase =
        args.installPhase or ''
          runHook preInstall
          install -Dm755 ${outDir}/${libFile} ${module}
          # The Zend API as bindgen saw it, to compare builds against other headers. Cargo keeps
          # it in build/ext-php-rs-<hash>/out, or build/ext-php-rs/<hash>/out since 1.9x.
          bindings=$(find ${outDir}/build -path '*/ext-php-rs[-/]*/out/bindings.rs' | head -n 1)
          if [ -z "$bindings" ]; then
            echo "no bindings.rs from ext-php-rs's build script under ${outDir}/build" >&2
            exit 1
          fi
          install -Dm644 "$bindings" "$out/share/ext-php-rs/bindings.rs"
          runHook postInstall
        '';

      # A module's tests link against the Zend API, which only PHP's embed SAPI provides.
      doCheck = args.doCheck or false;

      doInstallCheck = args.doInstallCheck or true;
      nativeInstallCheckInputs = build.nativeInstallCheckInputs or [ ] ++ nativeInstallCheckInputs;
      installCheckPhase =
        args.installCheckPhase or (
          ''
            runHook preInstallCheck
          ''
          + build.installCheck or ""
          + lib.optionalString build.canLoadIntoPhp ''
            ${lib.getExe php} -n -d extension=${module} \
              -r 'exit(extension_loaded("${extensionName}") ? 0 : 1);'
          ''
          + ''
            runHook postInstallCheck
          ''
        );

      passthru = {
        inherit (build) headers zts;
        inherit extensionName target;
        phpVersion = (php.unwrapped or php).version;
      }
      // passthru;
    };
}

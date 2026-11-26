# buildCargoArtifacts, in a native build and a portable one, of two fixtures:
#
# - tests/fixtures/features: one crate, with its dependencies from Cargo.lock (cargoLock), in a
#   release build, with a sourceRoot and a preBuild of its own;
# - tests/fixtures/workspace: an extension in a subdirectory (buildAndTestSubdir) that depends
#   on another member with a build script, under lints that an empty crate trips (denied and
#   forbidden), with its dependencies vendored by hash (cargoHash), in a debug build.
#
# Each is built before and after an edit to its source. The two modules must share one
# dependency build, which another PHP, feature set, toolchain or set of dependencies must not;
# neither module's build may compile a dependency or run bindgen again; and each must be built
# from its own source, not from the stubs of the dependency build (its output shows the edit).
#
# A hook that patches the vendored crates in the build directory must fail the build: it reads
# them from the store.
{
  pkgs,
  rustPhpPlatform,
  hostTarget,
}:
let
  inherit (pkgs) lib php84 php85;

  # The same toolchain under another name.
  otherToolchain = rustPhpPlatform.overrideScope (
    _: prev: {
      rustToolchain = pkgs.symlinkJoin {
        name = "other-rust-toolchain";
        paths = [ prev.rustToolchain ];
      };
    }
  );

  fixtures = {
    # Its build script sets a cfg where src/edited.rs exists, which changes the greeting.
    features = {
      root = ./fixtures/features;
      files = [
        "Cargo.toml"
        "Cargo.lock"
        "build.rs"
        "src/lib.rs"
      ];
      edit = "src/edited.rs";
      args = {
        pname = "hello";
        version = "0.1.0";
        cargoLock.lockFile = ./fixtures/features/Cargo.lock;
        # The name the source is unpacked under, which the stubs must be unpacked under too.
        sourceRoot = "source";
        # Without a newline at its end, before what the build adds to it.
        preBuild = "true";
      };
      others = [
        { buildFeatures = [ "shout" ]; }
        {
          cargoLock = {
            lockFile = null;
            lockFileContents = builtins.readFile ./fixtures/features/Cargo.lock + "\n";
          };
        }
      ];
      expected = {
        before = "Hello, PHP!";
        after = "Welcome, PHP!";
      };
    };

    # crates/greeting's build script reads the greeting from greeting.txt, if it exists.
    workspace = {
      root = ./fixtures/workspace;
      files = [
        "Cargo.toml"
        "Cargo.lock"
        "crates/ext"
        "crates/greeting/Cargo.toml"
        "crates/greeting/build.rs"
        "crates/greeting/src"
      ];
      edit = "crates/greeting/greeting.txt";
      args = {
        pname = "ext";
        version = "2.0.0";
        cargoHash = "sha256-+Xb8lPXexwuo8VPEKGZXR1RcVmi+dZebuOoJ1FXlEAs=";
        buildAndTestSubdir = "crates/ext";
        buildType = "debug";
      };
      others = [
        { buildType = "release"; }
        { cargoHash = lib.fakeHash; }
      ];
      # The module's build compiles the workspace's other crate too.
      ownCrates = [ "greeting" ];
      expected = {
        before = "Hello, PHP!";
        after = "Hello from the workspace, PHP!";
      };
    };
  };

  check =
    name:
    {
      root,
      files,
      edit,
      args,
      others,
      ownCrates ? [ ],
      expected,
    }:
    kind:
    let
      revision =
        edited:
        lib.fileset.toSource {
          inherit root;
          fileset = lib.fileset.unions (map (file: root + "/${file}") (files ++ lib.optional edited edit));
        };
      build =
        platform: extra:
        platform.buildRustPhpExtension (
          {
            php = php84;
            buildCargoArtifacts = true;
          }
          // args
          // kind
          // extra
        );
      module = edited: build rustPhpPlatform { src = revision edited; };
      before = module false;
      after = module true;
      # A fresh rlib or bindings.rs means Cargo silently recompiled a dependency or reran
      # bindgen: the restored files all have timestamp 1.
      verify =
        extension:
        extension.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            rebuilt=$(find target \( -name '*.rlib' -o -name bindings.rs \) -newermt @1 \
              ${lib.concatMapStringsSep " " (crate: "! -name 'lib${crate}-*.rlib'") ownCrates} -print)
            if [ -n "$rebuilt" ]; then echo "dependencies were rebuilt: $rebuilt" >&2; exit 1; fi
          '';
        });
      greet = extension: ''
        ${lib.getExe php84} -n -d extension=${verify extension}/lib/php/extensions/${extension.extensionName}.so \
          -r 'echo hello_world("PHP");'
      '';
    in
    assert before.drvPath != after.drvPath;
    assert before.cargoArtifacts.drvPath == after.cargoArtifacts.drvPath;
    # The stubs are named after the source's path, as stdenv unpacks it, not its `name`.
    assert
      (build rustPhpPlatform {
        src = {
          name = "another-name";
          outPath = "${revision true}";
        };
      }).cargoArtifacts.src.name == "source";
    assert lib.all
      (
        other:
        after.cargoArtifacts.drvPath != other.cargoArtifacts.drvPath && after.drvPath != other.drvPath
      )
      (
        map (extra: build rustPhpPlatform ({ src = revision true; } // extra)) (
          [ { php = php85; } ] ++ others
        )
        ++ [ (build otherToolchain { src = revision true; }) ]
      );
    pkgs.runCommand "cargo-artifacts-${name}" { } ''
      test "$(${greet before})" = '${expected.before}'
      test "$(${greet after})" = '${expected.after}'
      touch "$out"
    '';

  # ext-php-rs, patched where cargoSetupHook copies the vendored crates: the dependency build
  # must fail, with `message`, before it compiles anything.
  vendor-patch =
    name:
    { postPatch, message }:
    let
      inherit (fixtures.features) root files args;
      patched = rustPhpPlatform.buildRustPhpExtension (
        args
        // {
          php = php84;
          buildCargoArtifacts = true;
          src = lib.fileset.toSource {
            inherit root;
            fileset = lib.fileset.unions (map (file: root + "/${file}") files);
          };
          inherit postPatch;
        }
      );
      failure = pkgs.testers.testBuildFailure patched.cargoArtifacts;
    in
    pkgs.runCommand "cargo-artifacts-${name}" { } ''
      grep -Fq 'a hook changed the vendored crates' ${failure}/testBuildFailure.log
      grep -Fq '${message}' ${failure}/testBuildFailure.log
      if grep -q 'Compiling' ${failure}/testBuildFailure.log; then
        echo 'the dependency build compiled crates before it failed' >&2
        exit 1
      fi
      touch "$out"
    '';
  patchVendor = ''echo 'compile_error!("patched");' >> "$NIX_BUILD_TOP"/cargo-vendor-dir/ext-php-rs-0.16.4/src/lib.rs'';

  kinds = {
    native = { };
    portable = {
      target = hostTarget;
      zts = false;
    };
  };
in
{
  cargo-artifacts-native = check "native" fixtures.features kinds.native;
  cargo-artifacts-portable = check "portable" fixtures.features kinds.portable;
  cargo-artifacts-workspace-native = check "workspace-native" fixtures.workspace kinds.native;
  cargo-artifacts-workspace-portable = check "workspace-portable" fixtures.workspace kinds.portable;
  # A direct edit during patchPhase.
  cargo-artifacts-vendor-patch = vendor-patch "vendor-patch" {
    postPatch = patchVendor;
    message = "ext-php-rs-0.16.4/src/lib.rs";
  };
  # A registered hook that discovers crates with find. With a missing copy or a
  # placeholder file, find can succeed without patching anything.
  cargo-artifacts-vendor-patch-hook = vendor-patch "vendor-patch-hook" {
    postPatch = ''
      patchVendor() {
        find "$NIX_BUILD_TOP/cargo-vendor-dir" -type f -path '*/ext-php-rs-0.16.4/src/lib.rs' \
          -exec sed -i '1i compile_error!("patched");' {} +
      }
      preBuildHooks+=(patchVendor)
    '';
    message = "ext-php-rs-0.16.4/src/lib.rs";
  };
  cargo-artifacts-vendor-chmod = vendor-patch "vendor-chmod" {
    postPatch = ''
      chmod +x "$NIX_BUILD_TOP/cargo-vendor-dir/ext-php-rs-0.16.4/build.rs"
    '';
    message = "Vendor file type or executable bits differ:";
  };
}

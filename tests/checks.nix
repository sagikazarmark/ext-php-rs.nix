# The checks of the library itself (tests/default.nix adds the others): the example extension built natively and loaded, used through
# php.withExtensions and through an extension overlay, built with pkgsCross (on x86_64-linux,
# for aarch64-linux, loaded with qemu), and cross-compiled for every target as PIE archives
# (whose builds check each module's shared libraries, glibc floor or minimum macOS, and load
# the ones for this machine's PHP), buildRustPackage's build options in both kinds of build, and
# the devenv module's outputs. Loading the other cross-built modules needs a machine of their
# OS and CPU: .github/workflows/ci.yaml does that.
{
  pkgs,
  rustPhpPlatform,
  example,
}:

let
  inherit (pkgs)
    lib
    runCommand
    php84
    php85
    php86
    ;
  smokeTest = pkgs.callPackage ./smoke.nix { };
  # For the checks that run `php -r` instead of the example's .phpt tests: one whose output
  # depends on the build, one under qemu.
  smoke = {
    code = ''echo hello_world("ext-php-rs");'';
    expected = "Hello, ext-php-rs!";
  };
  exampleTests =
    name: php:
    rustPhpPlatform.runPhpTests {
      inherit name php;
      src = example.tests;
    };

  phps = [
    php84
    php85
    php86
  ];
  pie = example.pie phps;

  # Checks that only evaluate: each test's expr must equal its expected value, and the check
  # fails to evaluate with every one that does not.
  evalTests =
    name: tests:
    let
      failures = lib.runTests tests;
    in
    if failures == [ ] then
      runCommand "ext-php-rs-${name}" { } "touch $out"
    else
      throw "${name}: ${lib.generators.toPretty { } failures}";

  # The target of this machine's PHP, whose modules it loads.
  hostTarget =
    let
      platform = pkgs.stdenv.hostPlatform;
      arch = platform.parsed.cpu.name;
    in
    rustPhpPlatform.targets.${
      if platform.isDarwin then
        "${arch}-darwin"
      else
        "${arch}-linux-${if platform.isMusl then "musl" else "glibc"}"
    };
in
lib.listToAttrs (
  map (
    php:
    lib.nameValuePair "native-php${lib.versions.major php.version}${lib.versions.minor php.version}" (
      example.build php
    )
  ) phps
)
// {
  # A module from buildRustPhpExtension is an extension to nixpkgs' PHP.
  with-extensions = exampleTests "with-extensions" (
    php84.withExtensions ({ enabled, ... }: enabled ++ [ (example.build php84) ])
  );

  inherit pie;

  pie-asset-names = evalTests "pie-asset-names" {
    testAll = {
      expr = lib.sort lib.lessThan (lib.attrNames pie.archives);
      expected = lib.sort lib.lessThan (
        lib.mapCartesianProduct
          (
            {
              minor,
              arch,
              libc,
              ts,
            }:
            "php_hello-0.1.0_php${minor}-${arch}-${libc}-${ts}"
          )
          {
            minor = [
              "8.4"
              "8.5"
              "8.6"
            ];
            arch = [
              "x86_64"
              "arm64"
            ];
            libc = [
              "linux-glibc"
              "linux-musl"
              "darwin-bsdlibc"
            ];
            ts = [
              "nts"
              "zts"
            ];
          }
      );
    };
  };

  targets =
    let
      inherit (rustPhpPlatform.targets) aarch64-linux-musl x86_64-linux-glibc aarch64-darwin;
      custom = rustPhpPlatform.mkTarget {
        arch = "x86_64";
        libc = "glibc";
        glibc = "2.31";
      };
      refused = args: !(builtins.tryEval (rustPhpPlatform.mkTarget args).name).success;
    in
    evalTests "targets" {
      testGlibcCargoTarget = {
        expr = x86_64-linux-glibc.cargoTarget;
        expected = "x86_64-unknown-linux-gnu.2.28";
      };
      testMuslCargoTarget = {
        expr = aarch64-linux-musl.cargoTarget;
        expected = "aarch64-unknown-linux-musl";
      };
      testMuslPieArch = {
        expr = aarch64-linux-musl.pieArch;
        expected = "arm64";
      };
      testCustomGlibcZigTarget = {
        expr = custom.zigTarget;
        expected = "x86_64-linux-gnu.2.31";
      };
      testDarwinCargoTarget = {
        expr = aarch64-darwin.cargoTarget;
        expected = "aarch64-apple-darwin";
      };
      testDarwinZigTarget = {
        expr = aarch64-darwin.zigTarget;
        expected = "aarch64-macos.11.0";
      };
      testDarwinLibc = {
        expr = aarch64-darwin.libc;
        expected = "bsdlibc";
      };
      testDarwinSharedLibrary = {
        expr = aarch64-darwin.sharedLibrary;
        expected = ".dylib";
      };
      testUnknownArch = {
        expr = refused { arch = "riscv64"; };
        expected = true;
      };
      testUnknownOs = {
        expr = refused {
          arch = "x86_64";
          os = "windows";
        };
        expected = true;
      };
      testDarwinMusl = {
        expr = refused {
          arch = "aarch64";
          os = "darwin";
          libc = "musl";
        };
        expected = true;
      };
    };

  # buildRustPhpExtension's arguments read from a project's files.
  extension-args =
    let
      inherit (rustPhpPlatform) extensionArgs;
      fixture = extensionArgs { root = ./fixtures/extension-args; };
      # Without composer.json: the module is named after the Cargo package.
      features = extensionArgs { root = ./fixtures/features; };
      member = extensionArgs {
        root = ./fixtures/workspace/crates/ext;
        workspace = ./fixtures/workspace;
      };
      passedThrough = extensionArgs {
        root = ./fixtures/features;
        buildFeatures = [ "shout" ];
        version = "9.9.9";
      };
    in
    evalTests "extension-args" {
      testPname = {
        expr = fixture.pname;
        expected = "ext-demo";
      };
      testWorkspaceVersion = {
        expr = fixture.version;
        expected = "1.2.3";
      };
      testComposerExtensionName = {
        expr = fixture.extensionName;
        expected = "demo";
      };
      testLibName = {
        expr = fixture.libName;
        expected = "demo_ext";
      };
      testCargoExtensionName = {
        expr = features.extensionName;
        expected = "hello";
      };
      testNoLibName = {
        expr = features ? libName;
        expected = false;
      };
      # Only what the build reads.
      testSrc = {
        expr = lib.attrNames (builtins.readDir features.src);
        expected = [
          "Cargo.lock"
          "Cargo.toml"
          "build.rs"
          "src"
        ];
      };
      testWorkspaceMember = {
        expr = {
          inherit (member) pname version extensionName;
          lockFile = member.cargoLock.lockFile == ./fixtures/workspace/Cargo.lock;
          src = member.src == ./fixtures/workspace;
          workspace = member ? workspace;
        };
        expected = {
          pname = "ext";
          version = "2.0.0";
          extensionName = "ext";
          lockFile = true;
          src = true;
          workspace = false;
        };
      };
      testPassedThrough = {
        expr = {
          inherit (passedThrough) buildFeatures version;
          root = passedThrough ? root;
        };
        expected = {
          buildFeatures = [ "shout" ];
          version = "9.9.9";
          root = false;
        };
      };
    };

  # Arguments of the other kind of build are refused when evaluated: zts and allowedLibraries
  # without a target, and a target without zts = true or false.
  arguments =
    let
      inherit (rustPhpPlatform.targets) aarch64-linux-musl;
      evaluates =
        args:
        (builtins.tryEval
          (rustPhpPlatform.buildRustPhpExtension (example.args // { php = php84; } // args)).drvPath
        ).success;
    in
    evalTests "arguments" {
      testNative = {
        expr = evaluates { };
        expected = true;
      };
      testNativeZts = {
        expr = evaluates { zts = true; };
        expected = false;
      };
      testNativeAllowedLibraries = {
        expr = evaluates { allowedLibraries = [ ]; };
        expected = false;
      };
      testTarget = {
        expr = evaluates {
          target = aarch64-linux-musl;
          zts = false;
        };
        expected = true;
      };
      testTargetWithoutZts = {
        expr = evaluates { target = aarch64-linux-musl; };
        expected = false;
      };
      testTargetNonBoolZts = {
        expr = evaluates {
          target = aarch64-linux-musl;
          zts = "yes";
        };
        expected = false;
      };
    };

  # The devenv module, with stand-ins for the devenv options it reads: its outputs are the
  # builds above, the same derivations.
  devenv-module =
    let
      shell = lib.evalModules {
        specialArgs = { inherit pkgs; };
        modules = [
          ../modules/devenv.nix
          {
            options = {
              languages = {
                php.package = lib.mkOption { default = php84; };
                rust.enable = lib.mkOption { default = true; };
                rust.toolchainPackage = lib.mkOption { default = rustPhpPlatform.rustToolchain; };
                zig.enable = lib.mkOption { default = true; };
                zig.package = lib.mkOption { default = rustPhpPlatform.zig; };
              };
              outputs = lib.mkOption {
                type = lib.types.lazyAttrsOf lib.types.package;
                default = { };
              };
            };
          }
          {
            ext-php-rs.extensions.hello = {
              inherit (example) args;
              pie = {
                enable = true;
                php = phps;
              };
            };
          }
        ];
      };
      inherit (shell.config) outputs;
    in
    evalTests "devenv-module" {
      testOutputs = {
        expr = lib.attrNames outputs;
        expected = [
          "hello"
          "hello-pie"
        ];
      };
      testExtension = {
        expr = outputs.hello.drvPath;
        expected = (example.build php84).drvPath;
      };
      testPie = {
        expr = outputs.hello-pie.drvPath;
        expected = pie.drvPath;
      };
    };

  # An extension's flake publishing it for every PHP of nixpkgs (lib.mkPhpExtensionsOverlay),
  # with nixpkgs' Rust: loaded by name, as devenv's languages.php.extensions does, without
  # rebuilding PHP.
  php-extensions-overlay =
    let
      overlay = import ../lib/php-extensions-overlay.nix { inherit lib; } {
        extensions =
          { php, rustPhpPlatform, ... }:
          {
            hello = rustPhpPlatform.buildRustPhpExtension (example.args // { inherit php; });
          };
      };
      withOverlay = pkgs.appendOverlays [ overlay ];
    in
    assert withOverlay.php84.drvPath == php84.drvPath;
    exampleTests "php-extensions-overlay" (
      withOverlay.php85.withExtensions ({ enabled, all }: enabled ++ [ all.hello ])
    );

  # loadPieArchives' command, without Docker (CI's load jobs run its script with it): it finds
  # its helpers, selects archives by name (none here: one for another CPU, one for macOS on
  # this one), and refuses an unknown option.
  load-pie-archives =
    let
      this = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64";
      other = if pkgs.stdenv.hostPlatform.isAarch64 then "x86_64" else "arm64";
    in
    runCommand "ext-php-rs-load-pie-archives"
      { nativeBuildInputs = [ rustPhpPlatform.loadPieArchives ]; }
      ''
        mkdir archives tests
        touch archives/php_hello-0.1.0_php8.4-${other}-linux-glibc-nts.tgz
        touch archives/php_hello-0.1.0_php8.4-${this}-darwin-bsdlibc-nts.tgz
        status=0
        load-pie-archives archives tests 2> err || status=$?
        cat err
        [ "$status" -eq 1 ]
        grep -q 'no Linux .* archives' err
        status=0
        load-pie-archives --bogus archives tests 2> err || status=$?
        [ "$status" -eq 2 ]
        grep -q 'unknown option --bogus' err
        touch "$out"
      '';

  # runFpmTests fails when a child of FPM crashes, though FPM forks another and the test's
  # requests succeed: here after it sent the last response, as a crash in MSHUTDOWN would.
  fpm-child-crash =
    let
      failure = pkgs.testers.testBuildFailure (
        rustPhpPlatform.runFpmTests {
          name = "fpm-child-crash";
          php = php84;
          src = pkgs.writeTextDir "index.php" ''
            <?php
            echo 'ok';
            fastcgi_finish_request();
            usleep(500000);
            posix_kill(getmypid(), SIGSEGV);
          '';
          script = ''
            expect / ok
          '';
        }
      );
    in
    runCommand "ext-php-rs-fpm-child-crash" { } ''
      grep -q 'runFpmTests: a child of FPM crashed' ${failure}/testBuildFailure.log
      touch "$out"
    '';

  # A PHP overridden after the overlay (php.override { ztsSupport = true; … }: FrankenPHP's,
  # from the binary cache) rebuilds the overlay's extensions and nixpkgs' for itself: it starts
  # without a warning (an extension built for PHP without thread safety doesn't load).
  php-extensions-overlay-zts =
    let
      overlay = import ../lib/php-extensions-overlay.nix { inherit lib; } {
        extensions = [ example.args ];
      };
      withOverlay = pkgs.appendOverlays [ overlay ];
      php = withOverlay.frankenphp.php.withExtensions ({ enabled, all }: enabled ++ [ all.hello ]);
    in
    runCommand "ext-php-rs-php-extensions-overlay-zts"
      {
        code = ''echo PHP_ZTS, " ", hello_world("ZTS");'';
        expected = "1 Hello, ZTS!";
      }
      ''
        result=$(${lib.getExe php} -r "$code" 2>&1)
        echo "$result"
        [ "$result" = "$expected" ]
        touch "$out"
      '';
}
# buildRustPackage's build options, which a portable build passes to cargo zigbuild itself:
# a crate in a subdirectory (buildAndTestSubdir), a debug build (buildType), without the default
# features (buildNoDefaultFeatures) and with another one (buildFeatures). Each build is loaded
# into this machine's PHP, whose output shows the features (tests/fixtures/features: "Hello,
# <name>!" by default, "Hello, <name>." without the default features, in capitals with "shout").
// (
  let
    fixture = lib.fileset.toSource {
      root = ./fixtures/features;
      fileset = lib.fileset.unions [
        ./fixtures/features/Cargo.toml
        ./fixtures/features/Cargo.lock
        ./fixtures/features/src
      ];
    };
    # The fixture in crates/hello, not in a workspace, with its Cargo.lock at the root too.
    src = runCommand "hello-in-subdirectory" { } ''
      mkdir -p "$out/crates"
      cp -r ${fixture} "$out/crates/hello"
      cp ${fixture}/Cargo.lock "$out/Cargo.lock"
    '';
    build =
      args:
      rustPhpPlatform.buildRustPhpExtension (
        {
          pname = "hello";
          version = "0.1.0";
          cargoLock.lockFile = ./fixtures/features/Cargo.lock;
          inherit src;
          buildAndTestSubdir = "crates/hello";
          buildType = "debug";
          buildNoDefaultFeatures = true;
          buildFeatures = [ "shout" ];
          php = php84;
        }
        // args
      );
    test =
      name: extension:
      smokeTest {
        inherit name extension;
        php = php84;
        inherit (smoke) code;
        expected = "HELLO, EXT-PHP-RS.";
      };
  in
  {
    build-options-native = test "build-options-native" (build { });
    build-options-portable = test "build-options-portable" (build {
      target = hostTarget;
      zts = false;
    });
  }
)
// import ./cargo-artifacts.nix { inherit pkgs rustPhpPlatform hostTarget; }
// lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
  # A package for another Nix platform (pkgsCross), with nixpkgs' Rust, loaded into that
  # platform's PHP (without the SAPIs and extensions it does not need) under qemu.
  nix-cross-aarch64-linux =
    let
      cross = pkgs.pkgsCross.aarch64-multiplatform;
      php =
        (cross.php84.override {
          valgrindSupport = false;
          systemdSupport = false;
          fpmSupport = false;
          cgiSupport = false;
          phpdbgSupport = false;
          pearSupport = false;
          argon2Support = false;
        }).unwrapped;
      hello = (cross.callPackage ../lib { }).buildRustPhpExtension (example.args // { inherit php; });
    in
    runCommand "ext-php-rs-nix-cross-aarch64-linux"
      {
        nativeBuildInputs = [ pkgs.qemu-user ];
        inherit (smoke) code expected;
      }
      ''
        result=$(qemu-aarch64 ${php}/bin/php -n -d extension=${hello}/lib/php/extensions/hello.so -r "$code")
        echo "$result"
        [ "$result" = "$expected" ]
        touch "$out"
      '';
}

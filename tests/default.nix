# Everything that tests this flake, for one system, with the flake as a project gets it
# (devenv.nix's inputs: this flake, its nixpkgs, rust-overlay):
#
# - checks: devenv build outputs.checks (or outputs.checks.<name>)
# - load-tests: what .github/workflows/ci.yaml loads on Linux and macOS machines: every
#   portable archive (the example's and the real-world extensions'), each extension's .phpt
#   tests in tests/<name>/, PIE to install them with (tests/pie.sh), and PHP's run-tests.php for
#   a PHP without its own (tests/load-macos.sh)
# - example, example-pie: the example built for PHP 8.4, and its PIE archives
# - docs: the generated reference (docs/generate.nix)
{
  ext-php-rs,
  nixpkgs,
  rust-overlay,
  system,
}:

let
  # nixpkgs' own package set, not devenv's: the derivations, and so the binary cache's paths,
  # are those of a project using this flake.
  pkgs = nixpkgs.legacyPackages.${system};
  inherit (pkgs)
    lib
    php84
    php85
    php86
    ;

  # The library with a rust-overlay toolchain, as a project would use it.
  rustPhpPlatform = ext-php-rs.lib.makeRustPhpPlatform {
    inherit pkgs;
    rustToolchain = (rust-overlay.lib.mkRustBin { } pkgs).stable.latest.minimal;
  };

  example = pkgs.callPackage ./example.nix { inherit rustPhpPlatform; };
  realWorld = pkgs.callPackage ./real-world.nix { inherit rustPhpPlatform; };

  # The template's flake, with this flake as its ext-php-rs input.
  template =
    let
      outputs = (import ../templates/default/flake.nix).outputs {
        self = outputs // {
          outPath = ../templates/default;
        };
        inherit ext-php-rs nixpkgs rust-overlay;
      };
    in
    outputs;

  pie = pkgs.fetchurl {
    url = "https://github.com/php/pie/releases/download/1.5.5/pie.phar";
    hash = "sha256-LKDf9oaPG1PAlWJWdN7vOKxphYjgol5DIc2DSlt1U7w=";
  };
  example-pie = example.pie [
    php84
    php85
    php86
  ];
  tests = realWorld.tests // {
    hello = example.tests;
  };
  archives = [ example-pie ] ++ map rustPhpPlatform.mkPieArchive realWorld.portableBuilds;
  docs = import ../docs/generate.nix { inherit pkgs; };
in
{
  example = example.build php84;
  inherit docs example-pie;

  load-tests = pkgs.runCommand "ext-php-rs-load-tests" { } ''
    mkdir "$out"
    cp ${pie} "$out/pie.phar"
    tar -xf ${php84.unwrapped.src} --strip-components=1 --wildcards -C "$out" '*/run-tests.php'
    ${lib.concatMapStrings (archive: ''
      cp ${archive}/*.tgz "$out/"
    '') archives}
    mkdir "$out/tests"
    ${lib.concatStrings (
      lib.mapAttrsToList (name: dir: ''
        cp -r ${dir} "$out/tests/${name}"
      '') tests
    )}
  '';

  checks =
    import ./checks.nix { inherit pkgs rustPhpPlatform example; }
    // realWorld.checks
    // (
      let
        withOverlay = pkgs.extend ext-php-rs.overlays.default;
        withOverlayExample = withOverlay.callPackage ./example.nix { };
      in
      {
        # Native builds with nixpkgs' Rust, through the overlay.
        overlay = withOverlayExample.build withOverlay.php84;

        # With rust-overlay's overlay as well, portable builds use its toolchain: a module for
        # this machine, which its install check loads into PHP.
        overlay-rust-bin =
          let
            withRustBin = pkgs.appendOverlays [
              rust-overlay.overlays.default
              ext-php-rs.overlays.default
            ];
            platform = withRustBin.stdenv.hostPlatform;
            cpu = platform.parsed.cpu.name;
          in
          withRustBin.buildRustPhpExtension (
            (withRustBin.callPackage ./example.nix { }).args
            // {
              php = withRustBin.php84;
              target =
                withRustBin.rustPhpPlatform.targets.${
                  if platform.isDarwin then "${cpu}-darwin" else "${cpu}-linux-glibc"
                };
              threadSafety = "nts";
            }
          );

        # nixpkgs' Rust has no cross targets: a portable build says so when evaluated.
        overlay-cross =
          let
            cross = withOverlay.buildRustPhpExtension (
              withOverlayExample.args
              // {
                php = withOverlay.php84;
                target = withOverlay.rustPhpPlatform.targets.aarch64-linux-musl;
                threadSafety = "nts";
              }
            );
          in
          assert !(builtins.tryEval cross.drvPath).success;
          pkgs.runCommand "ext-php-rs-overlay-cross" { } "touch $out";
      }
    )
    # The template's checks (its .phpt tests, with the extension through its overlay, in PHP
    # 8.4, 8.5 and 8.6 and in ZTS, and its FrankenPHP and FPM tests), package and shell, built
    # here; its release archives are only evaluated (template-pie), as the example's are built.
    // lib.mapAttrs' (name: lib.nameValuePair "template-${name}") template.checks.${system}
    // {
      # docs/ has what docs/generate.nix generates: `update-docs` (devenv) copies it there.
      docs = pkgs.runCommand "ext-php-rs-docs-up-to-date" { } ''
        for file in functions.md devenv-options.md; do
          if ! diff -u ${../docs}/$file ${docs}/$file; then
            echo "docs/$file is out of date: run update-docs" >&2
            exit 1
          fi
        done
        touch "$out"
      '';

      template-package = template.packages.${system}.default;
      template-shell = template.devShells.${system}.default;
      template-pie =
        let
          inherit (template.packages.${system}) pie;
        in
        assert lib.length (lib.attrNames pie.passthru.archives) == 36;
        assert lib.isString pie.drvPath;
        pkgs.runCommand "ext-php-rs-template-pie" { } "touch $out";
    };
}

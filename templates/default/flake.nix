{
  description = "A PHP extension written in Rust with ext-php-rs";

  inputs = {
    ext-php-rs.url = "github:sagikazarmark/ext-php-rs.nix";
    # ext-php-rs's nixpkgs, so its binary cache (ext-php-rs.cachix.org) has the expensive parts
    # of portable builds: the PHP headers for each target and cargo-zigbuild.
    nixpkgs.follows = "ext-php-rs/nixpkgs";
    # The toolchain of portable builds, which gets each target's standard library added.
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      ext-php-rs,
    }:
    let
      inherit (nixpkgs) lib;

      # nixpkgs with rust-overlay's toolchains (for portable builds), ext-php-rs
      # (pkgs.rustPhpPlatform) and this flake's overlay (the extension in every PHP).
      forAllSystems =
        f:
        lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (
          system:
          f (
            nixpkgs.legacyPackages.${system}.appendOverlays [
              rust-overlay.overlays.default
              ext-php-rs.overlays.default
              self.overlays.default
            ]
          )
        );

      # buildRustPhpExtension's arguments: pname and version from Cargo.toml, extensionName from
      # composer.json (or the Cargo package's name), and the files the build reads.
      args = ext-php-rs.lib.extensionArgs { root = ./.; };
      inherit (args) extensionName;
    in
    {
      # The extension for every PHP of nixpkgs, built with nixpkgs' Rust against the PHP that
      # loads it:
      #
      #   pkgs.php.withExtensions ({ enabled, all }: enabled ++ [ all.hello ])
      #   devenv: languages.php.extensions = [ "hello" ];
      overlays.default = ext-php-rs.lib.mkPhpExtensionsOverlay { extensions = [ args ]; };

      packages = forAllSystems (pkgs: {
        # lib/php/extensions/hello.so, for nixpkgs' default PHP.
        default = pkgs.php.extensions.${extensionName};

        # nixpkgs' default PHP with the extension: `nix run .#php -- -r 'echo hello_world("Nix");'`.
        php = pkgs.php.withExtensions ({ enabled, all }: enabled ++ [ all.${extensionName} ]);

        # FrankenPHP with the extension, rebuilt for its thread-safe PHP:
        # `nix run .#frankenphp -- php-server --root tests/frankenphp --worker tests/frankenphp/index.php`.
        frankenphp = pkgs.frankenphp.override {
          php = pkgs.php.withExtensions ({ enabled, all }: enabled ++ [ all.${extensionName} ]);
        };

        # PIE's prebuilt binaries for a GitHub release: PHP 8.4, 8.5 and 8.6, NTS and ZTS, for x86_64
        # and arm64 Linux (glibc and musl) and macOS, with SHA256SUMS. Built on any of the
        # systems: on Linux, the macOS ones too.
        pie = pkgs.rustPhpPlatform.buildPieRelease {
          inherit args;
          php = [
            pkgs.php84
            pkgs.php85
            pkgs.php86
          ];
        };
      });

      checks = forAllSystems (
        pkgs:
        # tests/*.phpt, run with PHP 8.4, 8.5 and 8.6 with the extension loaded as users load it.
        lib.genAttrs [ "php84" "php85" "php86" ] (
          php:
          pkgs.rustPhpPlatform.runPhpTests {
            php = pkgs.${php};
            extensions = [ pkgs.${php}.extensions.${extensionName} ];
            src = ./tests;
          }
        )
        # Linux only: untested on macOS, where nixpkgs links FrankenPHP's PHP statically.
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          # tests/*.phpt with a thread-safe (ZTS) PHP, as FrankenPHP and PHP 8.6's official
          # images have: FrankenPHP's (nixpkgs' default PHP version, from its binary cache).
          zts = pkgs.rustPhpPlatform.runPhpTests {
            name = "php-tests-zts";
            inherit (pkgs.frankenphp) php;
            extensions = [ pkgs.frankenphp.php.extensions.${extensionName} ];
            src = ./tests;
          };

          # The extension in FrankenPHP's workers (tests/frankenphp/index.php): across requests,
          # after the workers restart, and with requests at once on PHP's threads.
          frankenphp = pkgs.rustPhpPlatform.runFrankenphpTests {
            inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) frankenphp;
            src = ./tests/frankenphp;
            script = ''
              expect "/?name=Nix" "Hello, Nix!"
              for i in 1 2 3; do
                restart_workers
                expect "/?name=restart$i" "Hello, restart$i!"
              done
              concurrently 20 "/?name=Nix"
            '';
          };
        }
      );

      # cargo build, clippy and rust-analyzer, against nixpkgs' default PHP.
      devShells = forAllSystems (pkgs: {
        default = pkgs.rustPhpPlatform.mkShell {
          inherit (pkgs) php;
          toolchain = pkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "rust-src"
              "rust-analyzer"
            ];
          };
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}

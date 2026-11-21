# A devenv module (https://devenv.sh) for ext-php-rs extensions: each one built against the
# shell's PHP, and its PIE archives, as outputs (`devenv build outputs.<name>`).
#
#   imports = [ inputs.ext-php-rs.devenvModules.default ];
#
#   ext-php-rs.extensions.hello = {
#     args = { pname = "hello"; version = "0.1.0"; src = ./.; cargoLock.lockFile = ./Cargo.lock; };
#     pie.enable = true; # outputs.hello-pie: every target for languages.php's PHP
#   };
{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.ext-php-rs;
  shell = config;
  targets = import ../lib/targets.nix { inherit lib; };

  extensionModule =
    { name, config, ... }:
    {
      options = {
        args = lib.mkOption {
          type = lib.types.lazyAttrsOf lib.types.raw;
          description = ''
            Arguments of `buildRustPhpExtension` that every build of the extension shares: `pname`,
            `version`, `src`, `cargoHash` or `cargoLock`, and optionally `cargoPackage`,
            `extensionName` and `buildRustPackage`'s arguments (`buildType`, `buildFeatures`,
            `cargoBuildFlags`, …).
          '';
          example = lib.literalExpression ''
            {
              pname = "hello";
              version = "0.1.0";
              src = ./.;
              cargoLock.lockFile = ./Cargo.lock;
            }
          '';
        };

        php = lib.mkOption {
          type = lib.types.package;
          default = shell.languages.php.package;
          defaultText = lib.literalExpression "config.languages.php.package";
          description = "The PHP the extension is built against, and loaded into to check it.";
        };

        output = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = name;
          description = "The output that builds the extension against `php` (`devenv build outputs.<output>`); null for none.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "The extension built against `php`: `lib/php/extensions/<extensionName>.so`.";
        };

        pie = {
          enable = lib.mkEnableOption "the extension's prebuilt binaries for PIE, cross-compiled for Linux and macOS";

          php = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ shell.languages.php.package ];
            defaultText = lib.literalExpression "[ config.languages.php.package ]";
            example = lib.literalExpression "[ pkgs.php84 pkgs.php85 ]";
            description = "The PHP versions to build for: one archive per PHP minor, target and thread safety.";
          };

          targets = lib.mkOption {
            type = lib.types.listOf (lib.types.enum (lib.attrNames targets));
            default = lib.attrNames targets;
            description = "The targets (OS, CPU and C library) to build for.";
          };

          threadSafety = lib.mkOption {
            type = lib.types.listOf (
              lib.types.enum [
                "nts"
                "zts"
              ]
            );
            default = [
              "nts"
              "zts"
            ];
            description = "The thread safety modes to build for.";
          };

          output = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "${name}-pie";
            description = "The output that builds the archives, their `.sha256` files and `SHA256SUMS`; null for none.";
          };

          package = lib.mkOption {
            type = lib.types.package;
            readOnly = true;
            description = "Every archive in one directory (`buildPieRelease`); `passthru.archives` has each one.";
          };
        };
      };

      config = {
        package = cfg.lib.buildRustPhpExtension (config.args // { inherit (config) php; });

        pie.package = cfg.lib.buildPieRelease {
          inherit (config) args;
          inherit (config.pie) php threadSafety;
          targets = map (target: cfg.lib.targets.${target}) config.pie.targets;
        };
      };
    };
in
{
  options.ext-php-rs = {
    rustToolchain = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = if shell.languages.rust.enable then shell.languages.rust.toolchainPackage else null;
      defaultText = lib.literalExpression "config.languages.rust.toolchainPackage, when languages.rust is enabled";
      description = ''
        The Rust toolchain the extensions are built with; null for nixpkgs' rustc and cargo.
        Portable builds add their target with `rustToolchain.override { targets = [ … ]; }` where
        the toolchain supports it (`languages.rust.toolchainFile`'s does); otherwise it must
        already have the targets' standard libraries (`languages.rust.targets`).
      '';
    };

    zig = lib.mkOption {
      type = lib.types.package;
      default = if shell.languages.zig.enable then shell.languages.zig.package else pkgs.zig;
      defaultText = lib.literalExpression "config.languages.zig.package when languages.zig is enabled, otherwise pkgs.zig";
      description = ''
        The zig that portable builds link with; bindgen uses the libclang of its LLVM, which it
        finds among the zig's build inputs. A zig from nixpkgs has it; zig-overlay's prebuilt
        ones (`languages.zig.version`) do not.
      '';
    };

    lib = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = "The ext-php-rs functions for this shell's packages, `rustToolchain` and `zig`: `buildRustPhpExtension`, `targets`, `mkPieRelease`, ….";
    };

    extensions = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule extensionModule);
      default = { };
      description = "Extensions to build, by name.";
    };
  };

  config = {
    ext-php-rs.lib = pkgs.callPackage ../lib { inherit (cfg) rustToolchain zig; };

    outputs = lib.mkMerge (
      lib.mapAttrsToList (
        _: extension:
        lib.optionalAttrs (extension.output != null) { ${extension.output} = extension.package; }
        // lib.optionalAttrs (extension.pie.enable && extension.pie.output != null) {
          ${extension.pie.output} = extension.pie.package;
        }
      ) cfg.extensions
    );
  };
}

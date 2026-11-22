{
  description = "Build PHP extensions written in Rust with ext-php-rs: for nixpkgs' PHP, and cross-compiled for any Linux or macOS as PIE's prebuilt binaries";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Documented in docs/functions.md.
      lib = import ./lib/flake-lib.nix { inherit lib; };

      # pkgs.rustPhpPlatform, with nixpkgs' Rust. Portable builds need a toolchain with each
      # target's standard library: apply rust-overlay's overlay too (rust-overlay.overlays.default,
      # pkgs.rust-bin), whose latest stable toolchain they then use, or set one with
      # pkgs.rustPhpPlatform.overrideScope (final: prev: { rustToolchain = …; }).
      # pkgs.buildRustPhpExtension is pkgs.rustPhpPlatform.buildRustPhpExtension.
      overlays.default = final: _prev: {
        rustPhpPlatform = final.callPackage ./lib { };
        inherit (final.rustPhpPlatform) buildRustPhpExtension;
      };

      devenvModules.default = ./modules/devenv.nix;

      # nix flake init -t github:sagikazarmark/ext-php-rs.nix
      templates.default = {
        path = ./templates/default;
        description = "A PHP extension written in Rust: an overlay for nixpkgs' PHP, PIE archives for GitHub releases, CI";
      };

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}

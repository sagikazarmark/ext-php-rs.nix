/**
  The flake's `lib` output: functions that don't need a package set, and `makeRustPhpPlatform`,
  which makes the [`rustPhpPlatform` scope](#rustphpplatform) for one.
*/
{ lib }:

{
  /**
    Makes the [`rustPhpPlatform` scope](#rustphpplatform) for a package set: the same as
    `pkgs.callPackage ./lib { … }`.

    # Inputs

    - `pkgs`: The package set to build with and for.
    - `rustToolchain`: The Rust toolchain (rustc and cargo). Default: nixpkgs' rustc and cargo. Portable builds
      need each target's standard library: a rust-overlay toolchain gets it added
      automatically, any other toolchain must already have it.
    - `zig`: The zig that portable builds compile and link with. Default: `pkgs.zig`. It must be a zig
      from nixpkgs, whose build inputs include the libclang of its LLVM.

    # Example

    ```nix
    rustPhpPlatform = ext-php-rs.lib.makeRustPhpPlatform {
      inherit pkgs;
      rustToolchain = (rust-overlay.lib.mkRustBin { } pkgs).stable.latest.minimal;
    };
    ```
  */
  makeRustPhpPlatform = { pkgs, ... }@args: pkgs.callPackage ./. (lib.removeAttrs args [ "pkgs" ]);

  /**
    The common targets: the same as
    [`rustPhpPlatform.targets`](#rustphpplatformtargets).
  */
  targets = import ./targets.nix { inherit lib; };

  /**
    Makes a target: the same as [`rustPhpPlatform.mkTarget`](#rustphpplatformmktarget).
  */
  mkTarget = import ./mk-target.nix { inherit lib; };

  /**
    Reads `buildRustPhpExtension`'s arguments from a project's files: the same as
    [`rustPhpPlatform.extensionArgs`](#rustphpplatformextensionargs).
  */
  extensionArgs = import ./extension-args.nix { inherit lib; };

  /**
    The extensions of a `buildRustPhpExtensions` set as a list, filtered: the same as
    [`rustPhpPlatform.collectExtensions`](#rustphpplatformcollectextensions).
  */
  collectExtensions = import ./collect-extensions.nix { inherit lib; };

  /**
    Makes an overlay that adds extensions to every PHP of nixpkgs (`php`, `php84`, `php85`, …),
    the way nixpkgs adds its own: to `php.extensions`. Each extension is built against the PHP
    that loads it, and users load it like one of nixpkgs':
    - `php.withExtensions ({ enabled, all }: enabled ++ [ all.<name> ])`
    - devenv: `languages.php.extensions = [ "<name>" ];`

    The overlay doesn't rebuild PHP, and several such overlays combine.

    # Inputs

    - `extensions`: Either a list of `buildRustPhpExtension`'s arguments (without `php`), each added under
      its `extensionName`; or a function from `{ pkgs, php, rustPhpPlatform }` to an attribute
      set of extensions built against `php`.
    - `rustPhpPlatform`: A function from the package set to the `rustPhpPlatform` to build with. Default:
      `pkgs.callPackage ./lib { }`, with nixpkgs' Rust.

    # Examples

    ```nix
    overlays.default = ext-php-rs.lib.mkPhpExtensionsOverlay {
      extensions = [ (ext-php-rs.lib.extensionArgs { root = ./.; }) ];
    };
    ```

    ```nix
    overlays.default = ext-php-rs.lib.mkPhpExtensionsOverlay {
      extensions = { php, rustPhpPlatform, ... }: {
        hello = rustPhpPlatform.buildRustPhpExtension {
          pname = "hello";
          version = "0.1.0";
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;
          inherit php;
        };
      };
    };
    ```
  */
  mkPhpExtensionsOverlay = import ./php-extensions-overlay.nix { inherit lib; };
}

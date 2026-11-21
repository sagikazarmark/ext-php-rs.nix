# An overlay that adds extensions to every PHP of nixpkgs (php, php84, php85, …), the way
# nixpkgs adds its own: to php.extensions, so that
#
#   php.withExtensions ({ enabled, all }: enabled ++ [ all.<name> ])
#
# and devenv's `languages.php.extensions = [ "<name>" ]` load them, each built against the
# PHP that loads it. For an extension's flake to publish as overlays.default:
#
#   overlays.default = ext-php-rs.lib.mkPhpExtensionsOverlay {
#     extensions = [ (ext-php-rs.lib.extensionArgs { root = ./.; }) ];
#   };
#
# or, for more than buildRustPhpExtension's arguments:
#
#   overlays.default = ext-php-rs.lib.mkPhpExtensionsOverlay {
#     extensions = { php, rustPhpPlatform, ... }: {
#       hello = rustPhpPlatform.buildRustPhpExtension { pname = "hello"; …; inherit php; };
#     };
#   };
{ lib }:

{
  # buildRustPhpExtension's arguments (without php) for each extension, added by its name
  # (extensionName, as buildRustPhpExtension defaults it); or a function from
  # { pkgs, php, rustPhpPlatform } to an attribute set of extensions built against `php`.
  extensions,
  # The rustPhpPlatform to build them with, from the package set: nixpkgs' Rust by default.
  rustPhpPlatform ? pkgs: pkgs.callPackage ./. { },
}:

final: prev:
let
  platform = rustPhpPlatform final;
  extensionsFor =
    if lib.isFunction extensions then
      extensions
    else
      { php, rustPhpPlatform, ... }:
      lib.listToAttrs (
        map (
          args:
          lib.nameValuePair (args.extensionName or args.cargoPackage or args.pname) (
            rustPhpPlatform.buildRustPhpExtension (args // { inherit php; })
          )
        ) extensions
      );
  phps = lib.filter (name: builtins.match "php[0-9]*" name != null) (lib.attrNames prev);
  # php.override { packageOverrides } (nixpkgs' way) changes the PHP the wrapper is rebuilt from,
  # but not the wrapper's own package set: its overrideAttrs rebuilds the wrapper from that PHP,
  # with the same extensions enabled (and the same derivation).
  addExtensions =
    php:
    (php.override (old: {
      packageOverrides = lib.composeExtensions (old.packageOverrides or (_: _: { })) (
        phpFinal: phpPrev: {
          # `php`'s extensions, with those of overlays before this one, and these.
          extensions =
            phpPrev.extensions
            // php.extensions
            // extensionsFor {
              pkgs = final;
              # The PHP without extensions, which the one with them is built from.
              php = phpFinal.php.unwrapped;
              rustPhpPlatform = platform;
            };
        }
      );
    })).overrideAttrs
      (_: { });
in
lib.genAttrs phps (name: addExtensions prev.${name})

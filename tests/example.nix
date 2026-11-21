# The example extension (module hello): the template's crate (templates/default), built the
# ways a project would: natively for a PHP from nixpkgs, and cross-compiled as PIE's prebuilt
# binaries. The template's own flake is checked as well (tests/default.nix).
{ rustPhpPlatform }:

let
  common = rustPhpPlatform.extensionArgs { root = ../templates/default; };
in
{
  args = common;

  build = php: rustPhpPlatform.buildRustPhpExtension (common // { inherit php; });

  # Every target, NTS and ZTS.
  pie =
    php:
    rustPhpPlatform.buildPieRelease {
      args = common;
      inherit php;
    };

  # Its .phpt tests: the template's.
  tests = ../templates/default/tests;
}

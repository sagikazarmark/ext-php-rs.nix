# A setup hook that sets environment variables, each unless already set (by the package's
# env), for buildRustPhpExtension and mkShell. A build input rather than env: nixpkgs builds a
# derivation's inputDerivation (everything it builds with, to fetch or cache without building
# it) from its arguments without env, so what the variables point at would be left out.
{
  lib,
  makeSetupHook,
  writeText,
}:

vars:

makeSetupHook { name = "ext-php-rs-setup-env"; } (
  writeText "ext-php-rs-setup-env.sh" (
    lib.concatStrings (
      lib.mapAttrsToList (name: value: ''
        export ${name}="''${${name}:-${value}}"
      '') vars
    )
  )
)

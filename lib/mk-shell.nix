# Documented at mkShell in lib/default.nix (docs/functions.md).
{
  mkShell,
  rustPlatform,
  rustToolchain,
}:

{
  php,
  # A toolchain with the components wanted (rust-overlay's .override { extensions = [ … ]; });
  # by default the scope's.
  toolchain ? rustToolchain,
  packages ? [ ],
  ...
}@args:

mkShell (
  removeAttrs args [
    "php"
    "toolchain"
  ]
  // {
    packages = [
      toolchain
      php
      (php.unwrapped or php).dev
      # libclang, as nixpkgs' builds get it: a build input rather than env, which the shell's
      # inputDerivation would leave out.
      rustPlatform.bindgenHook
    ]
    ++ packages;
  }
)

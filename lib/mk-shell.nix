# Documented at mkShell in lib/default.nix (docs/functions.md).
{
  lib,
  mkShell,
  llvmPackages,
  rustToolchain,
}:

{
  php,
  # A toolchain with the components wanted (rust-overlay's .override { extensions = [ … ]; });
  # by default the scope's.
  toolchain ? rustToolchain,
  packages ? [ ],
  env ? { },
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
    ]
    ++ packages;
    env = {
      LIBCLANG_PATH = "${lib.getLib llvmPackages.libclang}/lib";
    }
    // env;
  }
)

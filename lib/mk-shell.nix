# Documented at mkShell in lib/default.nix (docs/functions.md).
{
  lib,
  callPackage,
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
      # LIBCLANG_PATH, unless the shell's env sets it.
      (callPackage ./setup-env-hook.nix { } {
        LIBCLANG_PATH = "${lib.getLib llvmPackages.libclang}/lib";
      })
    ]
    ++ packages;
  }
)

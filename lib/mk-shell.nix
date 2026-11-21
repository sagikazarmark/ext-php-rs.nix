# A shell for `cargo build` (and clippy, rust-analyzer, …) in an ext-php-rs project, against
# a PHP from nixpkgs: ext-php-rs's build script runs its php and php-config, and bindgen needs
# libclang. Other arguments are mkShell's.
#
#   devShells.default = rustPhpPlatform.mkShell { php = pkgs.php84; };
#
# A module that `cargo build` builds on macOS needs `-undefined dynamic_lookup`, which
# buildRustPhpExtension sets itself: give cargo it in .cargo/config.toml (the template has it).
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

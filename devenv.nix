{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

let
  tests = import ./tests {
    inherit (inputs) ext-php-rs nixpkgs rust-overlay;
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  example = import ./tests/example.nix { rustPhpPlatform = config.ext-php-rs.lib; };
in
{
  imports = [ ./modules/devenv.nix ];

  env.LIBCLANG_PATH = "${lib.getLib pkgs.llvmPackages.libclang}/lib";

  packages = [
    pkgs.php84.unwrapped.dev
    pkgs.nixfmt-tree
    pkgs.statix
    pkgs.deadnix
    pkgs.shellcheck
    pkgs.actionlint
  ];

  languages = {
    php = {
      enable = true;
      package = pkgs.php84.withExtensions (
        { enabled, ... }: enabled ++ [ config.ext-php-rs.extensions.hello.package ]
      );
    };

    rust = {
      enable = true;
      channel = "stable";
    };
  };

  outputs = {
    inherit (tests)
      checks
      load-tests
      example
      example-pie
      docs
      ;
  };

  # outputs.hello: built with languages.rust's toolchain, against nixpkgs' PHP 8.4 (not
  # languages.php.package, which loads it).
  ext-php-rs.extensions.hello = {
    inherit (example) args;
    php = pkgs.php84;
  };

  scripts.update-docs = {
    description = "Regenerate docs/functions.md and docs/devenv-options.md";
    exec = ''
      set -euo pipefail
      out=$(devenv build outputs.docs | ${lib.getExe pkgs.jq} -r '."outputs.docs"')
      cp --no-preserve=mode "$out"/*.md "$DEVENV_ROOT/docs/"
    '';
  };

  scripts.lint = {
    description = "Format check and lint, as CI does";
    exec = ''
      set -e
      treefmt --ci
      actionlint .github/workflows/*.yaml templates/default/.github/workflows/*.yaml
      shellcheck -x lib/*.sh tests/*.sh
      statix check .
      deadnix --fail .
    '';
  };

  enterTest = ''
    set -euo pipefail
    lint
    # The example's .phpt tests with the shell's PHP, which has it loaded.
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    tar -xf ${pkgs.php84.unwrapped.src} -C "$work" --strip-components=1 --wildcards '*/run-tests.php'
    cp -r ${example.tests} "$work/tests"
    chmod -R u+w "$work/tests"
    NO_INTERACTION=1 REPORT_EXIT_STATUS=1 php "$work/run-tests.php" -P -q --show-diff "$work/tests"
  '';
}

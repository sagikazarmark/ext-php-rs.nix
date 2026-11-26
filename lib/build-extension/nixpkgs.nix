# buildRustPhpExtension without a target: a package of the package set, against `php` from the
# same set, built the way buildRustPackage builds for the set's host platform (another one with
# pkgsCross). The install check loads the module into `php` where the build platform can run it.
#
# Returns what sets this build apart from a portable one (portable.nix); default.nix does the
# rest.
{
  lib,
  stdenv,
  runCommand,
  rustPlatform,
}:

{
  php,
  zts,
  allowedLibraries,
  ...
}:

assert lib.assertMsg (zts == null)
  "buildRustPhpExtension: zts is for a target only; without one, the module has php's thread safety";
assert lib.assertMsg (
  allowedLibraries == null
) "buildRustPhpExtension: allowedLibraries is for a target only";

let
  unwrapped = php.unwrapped or php;
  # Whether the build platform runs the package set's PHP: not with pkgsCross.
  runsPhp = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  # include/php and bin/php-config: nixpkgs' own where `php` runs. Otherwise (pkgsCross) the
  # same headers, with a php-config that runs on the build platform and a stub for
  # `php -i` (write-php-stub.sh).
  headers =
    if runsPhp then
      lib.getDev unwrapped
    else
      runCommand "php-headers-${unwrapped.version}"
        {
          passthru = {
            inherit (unwrapped) version;
            target = null;
            zts = unwrapped.ztsSupport or false;
          };
        }
        ''
          mkdir -p "$out/include" "$out/bin"
          ln -s ${lib.getDev unwrapped}/include/php "$out/include/php"
          # The host's php-config, with a shell of the build platform.
          sed '1s|^#!.*|#!${stdenv.shell}|' ${lib.getDev unwrapped}/bin/php-config > "$out/bin/php-config"
          chmod +x "$out/bin/php-config"
          bash ${../write-php-stub.sh} "$out" ${stdenv.shell}
        '';
in
{
  inherit headers;
  zts = unwrapped.ztsSupport or false;

  darwin = stdenv.hostPlatform.isDarwin;
  rustTarget = stdenv.hostPlatform.rust.rustcTarget;
  # target/<this>/<profile>, where Cargo puts the build.
  cargoTripleDir = stdenv.hostPlatform.rust.cargoShortTarget;
  sharedLibrary = stdenv.hostPlatform.extensions.sharedLibrary;

  nativeBuildInputs = [ rustPlatform.bindgenHook ];
  setupEnv = {
    PHP = if runsPhp then "${unwrapped}/bin/php" else "${headers}/bin/php";
    PHP_CONFIG = "${headers}/bin/php-config";
  };

  # buildRustPackage's own phases, and no checks before loading the module. stdenv runs the
  # install check only where the build platform can run the package.
  canLoadIntoPhp = true;
}

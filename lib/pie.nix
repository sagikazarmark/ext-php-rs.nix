# PIE's pre-packaged binaries (https://github.com/php/pie, `download-url-method:
# pre-packaged-binary`): a gzipped tar per PHP minor, CPU, OS, C library and thread safety,
# with the module at its root as <extension>.so (on macOS too), named the way PIE looks for it
# among a GitHub release's assets.
{
  lib,
  runCommand,
  buildRustPhpExtension,
  targets,
}:

let
  allTargets = lib.attrValues targets;
  # php_{extension}-{version}_php{minor}-{arch}-{os}-{libc}-{nts|zts}.tgz, as PIE 1.5 builds
  # it (src/Platform/PrePackagedBinaryAssetName.php) for a non-debug PHP: libc is glibc or
  # musl on Linux, bsdlibc on macOS. `version` is the release's tag as Packagist reports it.
  pieAssetName =
    extension:
    let
      inherit (extension) target;
    in
    assert lib.assertMsg (target != null) "pieAssetName: ${extension.name} is not built for a target";
    "php_${extension.extensionName}-${extension.version}_php${lib.versions.majorMinor extension.phpVersion}-${target.pieArch}-${target.os}-${target.libc}-${
      if extension.zts then "zts" else "nts"
    }.tgz";

  # One archive and its .sha256 file, from a module built with a target.
  mkPieArchive =
    extension:
    let
      asset = pieAssetName extension;
    in
    runCommand (lib.removeSuffix ".tgz" asset)
      {
        passthru = {
          inherit asset extension;
        };
      }
      ''
        mkdir staging "$out"
        install -m755 ${extension}/lib/php/extensions/${extension.extensionName}.so staging/
        # A tgz, not a zip: Composer (inside PIE) extracts it without ext-zip or unzip.
        tar --create --format=ustar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@1 \
          --directory=staging ${extension.extensionName}.so \
          | gzip -n -9 > "$out/${asset}"
        cd "$out" && sha256sum ${asset} > ${asset}.sha256
      '';

  # Every archive of a release in one directory, with each one's .sha256 file and SHA256SUMS.
  mkPieRelease =
    {
      name,
      extensions,
    }:
    let
      # By name, so the order of `extensions` does not matter.
      archives = lib.sortOn (archive: archive.asset) (map mkPieArchive extensions);
      assets = map (archive: archive.asset) archives;
      duplicates = lib.filter (asset: lib.count (a: a == asset) assets > 1) assets;
    in
    assert lib.assertMsg (duplicates == [ ]) "mkPieRelease: more than one ${lib.head duplicates}";
    runCommand name
      {
        passthru.archives = lib.listToAttrs (
          map (archive: lib.nameValuePair (lib.removeSuffix ".tgz" archive.asset) archive) archives
        );
      }
      ''
        mkdir "$out"
        ${lib.concatMapStrings (archive: ''
          cp ${archive}/* "$out/"
        '') archives}
        cd "$out" && sha256sum ./*.tgz | sed 's| \./| |' > SHA256SUMS
      '';

  # A release of one extension: buildRustPhpExtension's `args`, built for every combination of
  # `php`, `targets` and `threadSafety`, through mkPieRelease.
  buildPieRelease =
    {
      args,
      php,
      targets ? allTargets,
      threadSafety ? [
        "nts"
        "zts"
      ],
      name ? null,
    }:
    let
      extensions =
        lib.mapCartesianProduct
          (
            {
              php,
              target,
              ts,
            }:
            buildRustPhpExtension (
              args
              // {
                inherit php target;
                zts = ts == "zts";
              }
            )
          )
          {
            inherit php;
            target = targets;
            ts = threadSafety;
          };
      first = lib.head extensions;
    in
    assert lib.assertMsg (
      extensions != [ ]
    ) "buildPieRelease: no PHP, target or thread safety to build for";
    mkPieRelease {
      name = if name != null then name else "php_${first.extensionName}-${first.version}";
      inherit extensions;
    };
in
{
  inherit
    pieAssetName
    mkPieArchive
    mkPieRelease
    buildPieRelease
    ;
}

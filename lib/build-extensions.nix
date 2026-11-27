# Documented at buildRustPhpExtensions in lib/default.nix (docs/functions.md): `args` built for
# every combination of `php`, `threadSafety`, `targets` and `variants`, as
# <php>.<threadSafety>.<target>.<variant>.
{
  lib,
  buildRustPhpExtension,
  targets,
}:

let
  allTargets = lib.attrValues targets;
  # The arguments each level sets, which a variant can't.
  matrixArgs = [
    "php"
    "target"
    "threadSafety"
  ];
in
{
  args,
  php,
  targets ? allTargets,
  threadSafety ? [
    "nts"
    "zts"
  ],
  variants ? {
    release = { };
  },
}:
let
  # A level's values by key: two values with the same key are refused.
  byKey =
    level: key: values:
    let
      keys = map key values;
      duplicates = lib.filter (k: lib.count (other: other == k) keys > 1) keys;
    in
    assert lib.assertMsg (
      duplicates == [ ]
    ) "buildRustPhpExtensions: ${level} ${lib.head duplicates} more than once";
    lib.listToAttrs (map (value: lib.nameValuePair (key value) value) values);

  # php84, from the version: the PHP's minor is what a portable build is for.
  phpKey =
    php:
    let
      version = (php.unwrapped or php).version;
    in
    "php${lib.versions.major version}${lib.versions.minor version}";

  threadSafetyKey =
    threadSafety:
    assert lib.assertMsg
      (lib.elem threadSafety [
        "nts"
        "zts"
      ])
      "buildRustPhpExtensions: threadSafety must be a list of \"nts\" and \"zts\", not ${
        lib.generators.toPretty { } threadSafety
      }";
    threadSafety;

  checkedVariants = lib.mapAttrs (
    name: variant:
    let
      set = lib.intersectLists matrixArgs (lib.attrNames variant);
    in
    assert lib.assertMsg (set == [ ])
      "buildRustPhpExtensions: variant ${name} sets ${lib.concatStringsSep ", " set}, which the matrix sets";
    variant
  ) variants;
in
lib.mapAttrs (
  _: php:
  lib.mapAttrs (
    _: threadSafety:
    lib.mapAttrs (
      _: target:
      lib.mapAttrs (
        _: variant:
        buildRustPhpExtension (
          args
          // variant
          // {
            inherit php target threadSafety;
          }
        )
      ) checkedVariants
    ) (byKey "target" (target: target.name) targets)
  ) (byKey "thread safety" threadSafetyKey threadSafety)
) (byKey "PHP" phpKey php)

# Documented at collectExtensions in lib/default.nix (docs/functions.md): the extensions of a
# buildRustPhpExtensions set (<php>.<threadSafety>.<target>.<variant>) as a list, filtered by
# the keys of each level and the target's arch, os and libc.
{ lib }:

extensions: filter:
let
  levels = [
    "php"
    "threadSafety"
    "target"
    "variant"
  ];
  targetAttrs = [
    "arch"
    "os"
    "libc"
  ];
  unknown = lib.subtractLists (levels ++ targetAttrs) (lib.attrNames filter);

  # A value matches unless the filter has the attribute: then it must be its value, or one of
  # its list.
  matches = name: value: !(filter ? ${name}) || lib.elem value (lib.toList filter.${name});

  # The extensions under a set, whose keys match the filter at each level.
  walk =
    levels: set:
    if levels == [ ] then
      [ set ]
    else
      lib.concatLists (
        lib.mapAttrsToList (
          key: value: lib.optionals (matches (lib.head levels) key) (walk (lib.tail levels) value)
        ) set
      );
in
assert lib.assertMsg (unknown == [ ])
  "collectExtensions: unknown filter ${lib.concatStringsSep ", " unknown}: it takes ${
    lib.concatStringsSep ", " (levels ++ targetAttrs)
  }";
lib.filter (extension: lib.all (attr: matches attr extension.target.${attr}) targetAttrs) (
  walk levels extensions
)

# Documented at extensionArgs in lib/default.nix (docs/functions.md).
{ lib }:

{
  # The crate's directory: its Cargo.toml.
  root ? src,
  # The workspace's directory, the repository's: its Cargo.toml's [workspace.package],
  # Cargo.lock and composer.json.
  workspace ? root,
  src ? null,
  ...
}@args:

assert lib.assertMsg (root != null) "extensionArgs: set root (the project's directory) or src";
let
  cargo = lib.importTOML (root + "/Cargo.toml");
  workspaceCargo = if workspace == root then cargo else lib.importTOML (workspace + "/Cargo.toml");
  inherit (cargo) package;
  # A field of the package, or the workspace's for `field.workspace = true`.
  field =
    name:
    let
      value = package.${name};
    in
    if lib.isAttrs value && value.workspace or false then
      workspaceCargo.workspace.package.${name}
    else
      value;

  composerFile = workspace + "/composer.json";
  composer = if builtins.pathExists composerFile then lib.importJSON composerFile else { };

  optional = path: lib.optional (builtins.pathExists path) path;
in
{
  pname = package.name;
  version = field "version";
  extensionName = composer.php-ext.extension-name or package.name;
  cargoLock.lockFile = workspace + "/Cargo.lock";
  src =
    if src != null then
      src
    else if workspace != root then
      workspace
    else
      lib.fileset.toSource {
        inherit root;
        fileset = lib.fileset.unions (
          [
            (root + "/Cargo.toml")
            (root + "/Cargo.lock")
            (root + "/src")
          ]
          ++ optional (root + "/build.rs")
          ++ optional (root + "/.cargo")
        );
      };
}
// lib.optionalAttrs (cargo ? lib.name) { libName = cargo.lib.name; }
// removeAttrs args [
  "root"
  "workspace"
]

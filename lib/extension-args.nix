# buildRustPhpExtension's arguments for a project, read from its files:
#
#   args = ext-php-rs.lib.extensionArgs { root = ./.; };
#   rustPhpPlatform.buildRustPhpExtension (args // { php = pkgs.php84; })
#
# - pname and version: Cargo.toml's package (a version inherited from the workspace too)
# - extensionName: composer.json's php-ext.extension-name, which PIE names the archives and the
#   module after; without one, the Cargo package's name, which ext-php-rs names the module after
# - libName: Cargo.toml's [lib] name, when it has one
# - cargoLock.lockFile: the workspace's Cargo.lock
# - src: what a single-crate project's build reads (Cargo.toml, Cargo.lock, src/, and build.rs
#   and .cargo/ where they exist), so that changing anything else (tests, CI, docs) rebuilds
#   nothing; for a crate in a workspace, the workspace's directory. Pass src for any other
#   layout (files the code includes, a narrower workspace).
#
# For a crate in a workspace, root is the crate's directory and workspace the workspace's:
#
#   ext-php-rs.lib.extensionArgs { root = ./crates/hello; workspace = ./.; }
#
# Any other argument is passed through, and overrides what is read.
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

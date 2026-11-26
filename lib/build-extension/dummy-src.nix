# Keep Cargo's view of the local packages (including path dependencies), but give
# every target and build script an empty body. No real Rust source is an input.
{ lib, runCommand }:
src:
let
  root = toString src;
  entries = dir: if builtins.pathExists dir then builtins.readDir dir else { };
  # Copy only Cargo metadata, not the source's directory skeleton. Adding a
  # directory of ordinary Rust modules mustn't invalidate the dependency build.
  discover =
    prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        let
          path = prefix + name;
        in
        if
          lib.elem name [
            "Cargo.toml"
            "Cargo.lock"
            ".cargo"
          ]
        then
          [ path ]
        else if
          type == "directory"
          && !(lib.elem name [
            ".git"
            "target"
            ".devenv"
          ])
        then
          discover (path + "/")
        else
          [ ]
      ) (entries "${root}/${prefix}")
    );
  targets =
    manifest:
    let
      dir = dirOf "${root}/${manifest}";
      toml = builtins.fromTOML (builtins.readFile "${root}/${manifest}");
      auto =
        sub:
        lib.mapAttrsToList
          (name: type: if type == "directory" then "${sub}/${name}/main.rs" else "${sub}/${name}")
          (
            lib.filterAttrs (name: type: type == "directory" || lib.hasSuffix ".rs" name) (
              entries "${dir}/${sub}"
            )
          );
      paths = [
        "build.rs"
        "src/lib.rs"
        "src/main.rs"
      ]
      ++ lib.optional (builtins.isString (toml.package.build or false)) toml.package.build
      ++ lib.concatMap auto [
        "src/bin"
        "examples"
        "tests"
        "benches"
      ]
      ++ lib.concatMap (t: lib.optional (t ? path) t.path) (
        [ (toml.lib or { }) ]
        ++ toml.bin or [ ]
        ++ toml.example or [ ]
        ++ toml.test or [ ]
        ++ toml.bench or [ ]
      );
    in
    map (
      p:
      let
        path = toString (/. + builtins.unsafeDiscardStringContext "${dir}/${p}");
      in
      assert lib.assertMsg (lib.hasPrefix "${root}/" path)
        "buildCargoArtifacts: target ${p} is outside src";
      lib.removePrefix "${root}/" path
    ) (lib.filter (p: builtins.pathExists "${dir}/${p}") paths);
  metadata = discover "";
  files = lib.unique (lib.concatMap targets (lib.filter (p: baseNameOf p == "Cargo.toml") metadata));
  # The name stdenv unpacks src under (its store path's, not its derivation's: an output
  # other than `out` has another), so that a sourceRoot set for it fits the stubs too.
  name = if lib.isStorePath root then lib.substring 33 (-1) (baseNameOf root) else baseNameOf root;
in
assert lib.assertMsg (
  builtins.readFileType root == "directory"
) "buildCargoArtifacts: src must be a directory, not an archive to unpack (${root})";
runCommand name { } ''
  mkdir -p "$out"
  cd "$out"
  ${lib.concatMapStrings (p: ''
    mkdir -p ${lib.escapeShellArg (dirOf ("./" + p))}
    cp -r ${
      builtins.path {
        path = "${root}/${p}";
        name = "cargo-input";
      }
    } ${lib.escapeShellArg ("./" + p)}
  '') metadata}
  for file in ${lib.escapeShellArgs files}; do
    mkdir -p "$(dirname "$file")"
    # rustc records env! inputs in dep-info. The real build unsets this one:
    # even a build.rs, proc macro or optional path dependency with an identical
    # source mtime cannot reuse its stub (no Cargo layout assumptions).
    echo 'const _: &str = env!("EXT_PHP_RS_DUMMY_BUILD"); fn main() {}' > "$file"
  done
''

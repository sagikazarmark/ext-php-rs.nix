# The generated reference: docs/functions.md, from the doc comments in lib/flake-lib.nix and
# lib/default.nix (nixdoc), and docs/devenv-options.md, from modules/devenv.nix's options.
#
# `devenv build outputs.docs` builds it, `update-docs` copies it into docs/, and the `docs`
# check fails if the copies in docs/ are out of date.
{ pkgs }:

let
  inherit (pkgs) lib;

  # The module alone: its defaults that read the rest of devenv's configuration have a
  # defaultText, so they aren't evaluated.
  devenvModule = lib.evalModules {
    modules = [
      ../modules/devenv.nix
      {
        _module.check = false;
        _module.args.pkgs = pkgs;
      }
    ];
  };

  # A heading per option, with its description, type, default and example.
  devenvOptions =
    let
      options = lib.filter (option: option.visible && !option.internal) (
        lib.optionAttrSetToDocList devenvModule.options.ext-php-rs
      );
      # A literalExpression or literalMD, inline or as a block.
      value =
        label: v:
        let
          text = lib.removeSuffix "\n" v.text;
        in
        if v._type == "literalMD" then
          "**${label}:** ${text}"
        else if lib.hasInfix "\n" text then
          "**${label}:**\n\n```nix\n${text}\n```"
        else
          "**${label}:** `${text}`";
      render =
        option:
        lib.concatStringsSep "\n\n" (
          [
            "## `${option.name}`"
            (lib.removeSuffix "\n" option.description)
            "**Type:** ${option.type}${lib.optionalString option.readOnly " (read-only)"}"
          ]
          ++ lib.optional (option ? default) (value "Default" option.default)
          ++ lib.optional (option ? example) (value "Example" option.example)
        );
    in
    pkgs.writeText "devenv-options.md" (
      ''
        # devenv module options

        <!-- Generated from modules/devenv.nix: run `update-docs` (devenv) after changing it. -->

        The options of [`devenvModules.default`](../modules/devenv.nix).

      ''
      + lib.concatMapStringsSep "\n\n" render options
      + "\n"
    );

  # Turns nixdoc's CommonMark into GitHub's: no {#anchor} attributes on headings (GitHub makes
  # its own anchors), and every heading one level down, under the page's title. Code blocks are
  # left alone.
  githubMarkdown = pkgs.writeText "github-markdown.awk" ''
    /^```/ { fence = !fence }
    !fence && /^#/ {
      sub(/ *\{#[^}]*\} *$/, "")
      $0 = "#" $0
    }
    { print }
  '';
in
pkgs.runCommand "ext-php-rs-docs"
  {
    nativeBuildInputs = [
      pkgs.nixdoc
      pkgs.gawk
    ];
  }
  ''
    mkdir "$out"

    {
      nixdoc --prefix ext-php-rs --category lib --description '`ext-php-rs.lib`' \
        --file ${../lib/flake-lib.nix}
      nixdoc --prefix "" --category rustPhpPlatform --description '`rustPhpPlatform`' \
        --file ${../lib/default.nix}
    } | awk -f ${githubMarkdown} > body.md

    {
      cat <<'EOF'
    # Functions

    <!-- Generated from the doc comments in lib/: run `update-docs` (devenv) after changing them. -->

    The flake's [`lib`](#ext-php-rslib) output has the functions that need no package set, and
    `makeRustPhpPlatform`, which makes the [`rustPhpPlatform`](#rustphpplatform) scope of
    functions for a package set. The overlay adds that scope as `pkgs.rustPhpPlatform`, and the
    devenv module as `config.ext-php-rs.lib`.

    EOF
      # An index of the functions, by section.
      awk '
        /^```/ { fence = !fence }
        fence { next }
        /^## / { title = substr($0, 4); print "- " title }
        /^### `/ {
          name = $0; sub(/^### /, "", name)
          anchor = tolower(name); gsub(/[^a-z0-9 -]/, "", anchor); gsub(/ /, "-", anchor)
          print "  - [" name "](#" anchor ")"
        }
      ' body.md
      echo
      cat body.md
    } > "$out/functions.md"

    cp ${devenvOptions} "$out/devenv-options.md"
  ''

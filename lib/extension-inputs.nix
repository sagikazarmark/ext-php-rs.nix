# Documented at mkExtensionInputs in lib/default.nix (docs/functions.md): every extension's
# inputDerivation without its source, as the references of one file.
{
  lib,
  writeText,
}:

{
  extensions,
  name ? "php-extension-inputs",
}:
let
  # The source is left out, so it isn't even evaluated. cargoDeps stays the extension's own: with
  # cargoHash, buildRustPackage vendors the dependencies from the source.
  inputsOf =
    extension:
    (extension.overrideAttrs {
      src = null;
      inherit (extension) cargoDeps;
    }).inputDerivation;
in
assert lib.assertMsg (extensions != [ ]) "mkExtensionInputs: no extensions";
writeText name (lib.concatMapStrings (extension: "${inputsOf extension}\n") extensions)

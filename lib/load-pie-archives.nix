# Documented at loadPieArchives in lib/default.nix (docs/functions.md).
{
  lib,
  runCommand,
  makeWrapper,
  bash,
  coreutils,
  findutils,
  gnused,
  gnutar,
  gzip,
}:

runCommand "load-pie-archives"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta.mainProgram = "load-pie-archives";
  }
  ''
    libexec=$out/libexec/ext-php-rs
    install -Dm644 ${./load-lib.sh} "$libexec/load-lib.sh"
    install -Dm644 ${./load-pie-archives.sh} "$libexec/load-pie-archives.sh"
    # Docker (or DOCKER) from the user's PATH.
    makeWrapper ${lib.getExe bash} "$out/bin/load-pie-archives" \
      --add-flags "$libexec/load-pie-archives.sh" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          findutils
          gnused
          gnutar
          gzip
        ]
      }
  ''

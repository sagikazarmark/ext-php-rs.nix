# A target an extension can be cross-compiled for, from its OS, CPU and C library: Linux with
# glibc (from a floor version on) or musl, or macOS (from a minimum version on). targets.nix
# has the common ones.
{ lib }:

{
  arch,
  os ? "linux",
  libc ? if os == "darwin" then "bsdlibc" else "glibc",
  # The oldest glibc the module loads on: zig links against this version's symbols.
  glibc ? "2.28",
  # The oldest macOS the module loads on.
  macos ? "11.0",
}:
let
  isDarwin = os == "darwin";
  abi = if libc == "musl" then "musl" else "gnu";
  glibcSuffix = lib.optionalString (libc == "glibc") ".${glibc}";
  rustTarget = if isDarwin then "${arch}-apple-darwin" else "${arch}-unknown-linux-${abi}";
in
assert lib.assertMsg (lib.elem arch [
  "x86_64"
  "aarch64"
]) "mkTarget: arch must be x86_64 or aarch64, not ${arch}";
assert lib.assertMsg (lib.elem os [
  "linux"
  "darwin"
]) "mkTarget: os must be linux or darwin, not ${os}";
assert lib.assertMsg (
  if isDarwin then
    libc == "bsdlibc"
  else
    lib.elem libc [
      "glibc"
      "musl"
    ]
) "mkTarget: libc ${libc} is not one of ${os}'s";
{
  inherit arch os libc;
  glibc = if libc == "glibc" then glibc else null;
  macos = if isDarwin then macos else null;
  name = if isDarwin then "${arch}-darwin" else "${arch}-linux-${libc}";
  # The Nix system whose PHP can load the module, given the same C library.
  system = "${arch}-${os}";
  # The target triple, as rustc names it (and the standard library to add).
  inherit rustTarget;
  # The triple for cargo zigbuild --target: rustTarget with the glibc floor. cargo-zigbuild and zig read the glibc version from the end of the target; cargo-zigbuild
  # the minimum macOS from MACOSX_DEPLOYMENT_TARGET.
  cargoTarget = rustTarget + glibcSuffix;
  zigTarget = if isDarwin then "${arch}-macos.${macos}" else "${arch}-linux-${abi}${glibcSuffix}";
  # PHP's configure, as --host.
  configureHost = if isDarwin then rustTarget else "${arch}-linux-${abi}";
  # The file Cargo links the cdylib to.
  sharedLibrary = if isDarwin then ".dylib" else ".so";
  # The CPU as PIE names it, from php_uname('m').
  pieArch =
    {
      x86_64 = "x86_64";
      aarch64 = "arm64";
    }
    .${arch};
}

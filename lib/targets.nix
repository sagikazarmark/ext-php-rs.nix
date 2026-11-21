# The targets an extension can be cross-compiled for, one per OS, CPU and C library: Linux
# with glibc 2.28 or later or musl, and macOS 11.0 or later. mkTarget makes others.
{
  lib,
  mkTarget ? import ./mk-target.nix { inherit lib; },
}:

{
  x86_64-linux-glibc = mkTarget {
    arch = "x86_64";
    libc = "glibc";
  };
  aarch64-linux-glibc = mkTarget {
    arch = "aarch64";
    libc = "glibc";
  };
  x86_64-linux-musl = mkTarget {
    arch = "x86_64";
    libc = "musl";
  };
  aarch64-linux-musl = mkTarget {
    arch = "aarch64";
    libc = "musl";
  };
  x86_64-darwin = mkTarget {
    arch = "x86_64";
    os = "darwin";
  };
  aarch64-darwin = mkTarget {
    arch = "aarch64";
    os = "darwin";
  };
}

# How portable builds work

A portable build (`buildRustPhpExtension` with a `target`) cross-compiles a module from any
platform. The module loads in any PHP of that target and thread safety, not only Nix's.

ext-php-rs's build script runs `$PHP -i` and `$PHP_CONFIG --includes`. It reads four `php -i`
entries (version, PHP API, thread safety, debug build) and the include path, then runs bindgen
over the headers. It never runs the target's PHP, so a portable build gives it the target's
headers and a stub `php` instead.

## Headers

[`lib/php-headers.nix`](../lib/php-headers.nix) takes nixpkgs' PHP source, runs `./configure`
for the target with `zig cc` as the cross compiler, then `make install-headers`, and keeps the
`php-config` that configure writes. Nothing is compiled, and it takes about a minute.

A build without a target uses nixpkgs' PHP itself: its headers and `php-config` (its `dev`
output), and its `php`.

**Why configured headers:** they must come from a PHP configured for the target platform and
thread safety, because `php_config.h` changes the layout of the structs ext-php-rs binds. A ZTS
build on Linux adds timer fields to the executor globals, and the core globals differ between
Linux and macOS. With the wrong headers, a module builds and then misreads PHP's memory.

**Always a cross configure**, even for the build platform's own CPU, so the result doesn't
depend on where it's built.

**Presets:** two configure checks need to run a program, so they're preset to what PHP's own
build finds:

- `php_cv_have_stack_limit=yes`: otherwise `ZEND_CHECK_STACK_LIMIT` and the executor globals'
  call stack fields go missing.
- `php_cv_have_global_register_vars=yes` on Linux, where PHP is built with gcc: otherwise the
  Zend VM kind changes, and with it PHP 8.5's `zend_vm_opcode_handler_t`. PHP on macOS is built
  with clang, which has no global register variables, like zig.

## The `php` stub

[`lib/write-php-stub.sh`](../lib/write-php-stub.sh) writes a `bin/php` script that answers
`php -i` from those headers. A `pkgsCross` build, whose PHP can't run on the build platform
either, uses one with that PHP's own headers.

## Compiling and linking

Builds use `cargo zigbuild`, against the target's glibc floor (default 2.28), musl, or minimum
macOS (default 11.0).

bindgen uses the libclang of zig's own LLVM, because zig's builtin headers (`arm_neon.h`, …) only
parse with the same clang version. The scope finds it among zig's build inputs, so any zig from
nixpkgs works.

### C dependencies

The C dependencies of `-sys` crates (zstd-sys, libz-sys, openssl-sys, …) are built from their
vendored sources by zig and linked statically.

`buildRustPackage` tells those crates to link the system's libraries through pkg-config instead,
which in a portable build would be Nix's, for the build platform. So a portable build sets
`dontCargoUseSystemLibs`. A build without a target keeps nixpkgs' behaviour, and needs the
libraries and `pkg-config` as inputs.

A build script that compiles a program and runs it (aws-lc-sys's compiler check, for example)
gets Nix's dynamic loader through `LDFLAGS` when the target is a glibc target of the build
platform's own CPU. The Nix sandbox has no `/lib64/ld-linux-*.so`, which zig gives glibc
executables.

### macOS

macOS targets build with nixpkgs' macOS SDK (the scope's `macosSdk`: Apple's Command Line Tools
SDK, as nixpkgs fetches it), given to zig and bindgen as `SDKROOT`. So a macOS module builds the
same way on Linux, frameworks included. The module's install name is `<extensionName>.so`, not
the build's path.

This needs cargo-zigbuild 0.24 or later, which keeps rustc's `-exported_symbols_list` file with
the flag for zig 0.16 and later ([#479](https://github.com/rust-cross/cargo-zigbuild/issues/479)),
and gives zig the minimum macOS from `MACOSX_DEPLOYMENT_TARGET`
([#488](https://github.com/rust-cross/cargo-zigbuild/issues/488)). nixpkgs has 0.23.4, so the
scope builds 0.24.1 until it catches up.

## Checking

A module built for another platform can't be loaded where it's built, so its install check reads
it instead: the shared libraries it needs, its glibc symbol versions, or its minimum macOS.

Where the build machine's PHP is of the module's platform (the x86_64 glibc NTS modules on an
x86_64 Linux, the arm64 macOS NTS ones on a Mac), the check loads it too. CI loads the others on
a machine of their OS and CPU: into the official Docker images on Linux, and into setup-php's PHP
on macOS.

## Verification

Verified with [restate-php](https://github.com/restate-php/restate)'s extension (ext-php-rs
0.16.4, PHP 8.4.27 and 8.5.12 from nixpkgs), across all 16 combinations of PHP 8.4 and 8.5, NTS
and ZTS, x86_64 and arm64, and glibc and musl:

- The generated bindings are identical to those generated from the official `php` Docker images'
  own headers.
- Every module loads into the matching official image.
- Debug builds pass that extension's test suite there.

For macOS, the example's bindings for arm64 NTS match those generated from nixpkgs' PHP on macOS
(configured natively), apart from the parameter names of two function pointers in the SDK's
`FILE`.

To check another PHP release, compare a build's `share/ext-php-rs/bindings.rs` with bindings
generated from the image's `/usr/local/include/php`.

## Caveats

- ext-php-rs passes the macOS SDK to bindgen whenever its build script runs on macOS, even for
  another target. Portable builds on macOS put an `xcrun` that fails first on `PATH`.
- Panic messages contain source paths, and Nix's build directory has a random name on macOS.
  Builds remap it to `/build`, so each build platform reproduces its own builds. A module built
  on macOS and the same module built on Linux still differ.
- With `buildCargoArtifacts`, the archive of compiled dependencies records the build
  directory, so two builds of it differ wherever that directory's name is random.
- zig-linked musl modules list `libc.so` as their C library (musl's loader resolves it to
  itself) and contain their own unwinder (no `libgcc_s`).
- Modules are built against nixpkgs' PHP patch release. A module loads into later patch releases
  of the same minor, and into earlier ones as long as it uses no function added since. Debug
  builds reference every bound function, so they need at least that patch release.
- Until nixpkgs has cargo-zigbuild 0.24, the scope builds it from source, once.
- PIE archives are for Linux and macOS: PIE on Windows wants DLLs.
- Portable builds run bindgen with zig's libclang, which old bindgen releases may misread:
  [kcs/lopdf](https://packagist.org/packages/kcs/lopdf) 0.1.0 (ext-php-rs 0.13.1, bindgen 0.68.1)
  gets opaque Zend structs with zig 0.17's libclang 22, though it builds natively with nixpkgs'
  libclang 21.

# ext-php-rs.nix

[![CI](https://img.shields.io/github/actions/workflow/status/sagikazarmark/ext-php-rs.nix/ci.yaml?style=flat-square)](https://github.com/sagikazarmark/ext-php-rs.nix/actions/workflows/ci.yaml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/sagikazarmark/ext-php-rs.nix/badge?style=flat-square)](https://securityscorecards.dev/viewer/?uri=github.com/sagikazarmark/ext-php-rs.nix)

Build PHP extensions written in Rust with [ext-php-rs](https://github.com/extphprs/ext-php-rs), with Nix:

- **For a PHP from nixpkgs**, as a package that `php.withExtensions` accepts, on `buildRustPackage`. It builds for other Nix platforms with `pkgsCross`, and an extension's flake can publish it for every PHP of nixpkgs with an overlay.
- **As portable modules for Linux and macOS**, cross-compiled (x86_64 or aarch64; glibc, musl or macOS; NTS or ZTS) from any platform. The modules load in any PHP of that kind (the official Docker images, distribution packages, Homebrew's), not only Nix's.
- **As [PIE](https://github.com/php/pie)'s prebuilt binaries:** archives named the way `pie install` looks for them on a GitHub release, with `SHA256SUMS`.

As a library of functions, an overlay, or a [devenv](https://devenv.sh) module.

## Getting started

### Template

```shell
nix flake init -t github:sagikazarmark/ext-php-rs.nix
```

starts an extension project (`templates/default/`) whose flake has:

- **`overlays.default`**, for Nix users: the extension in every PHP of nixpkgs (`all.hello` in `php.withExtensions`, `languages.php.extensions = [ "hello" ]` in devenv)
- **`packages.pie`**, for GitHub releases: PIE's archives for PHP 8.4, 8.5 and 8.6, every target, NTS and ZTS, with `SHA256SUMS`
- **`checks`**: `tests/*.phpt` run with PHP 8.4, 8.5 and 8.6, with the extension loaded through the overlay
- **`devShells.default`**: `cargo build`, clippy and rust-analyzer against nixpkgs' PHP

It reads the package's name and version from `Cargo.toml`, and the module's name from `composer.json` (`lib.extensionArgs`).

It also has a `composer.json` for PIE, CI, and a release workflow that publishes the archives when a tag is pushed. Its README covers renaming and releasing.

### Binary cache

CI pushes what this flake builds to [ext-php-rs.cachix.org](https://ext-php-rs.cachix.org): the PHP headers for each target (a `./configure` each) and cargo-zigbuild, which portable builds would otherwise build first.

```shell
cachix use ext-php-rs
```

The cache only has what this flake's nixpkgs builds. A project gets it by taking nixpkgs from this flake (`nixpkgs.follows = "ext-php-rs/nixpkgs"`, as the template does), not by making this flake follow its own nixpkgs, which rebuilds them. Cache a project's own builds in a cache of its own: the template's workflows push to one when the repository variable `CACHIX_CACHE` and the secret `CACHIX_AUTH_TOKEN` are set.

### Flake

```nix
{
  inputs = {
    ext-php-rs.url = "github:sagikazarmark/ext-php-rs.nix";
    # Its nixpkgs, for the binary cache (above).
    nixpkgs.follows = "ext-php-rs/nixpkgs";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, rust-overlay, ext-php-rs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
      rustPhpPlatform = ext-php-rs.lib.makeRustPhpPlatform {
        inherit pkgs;
        # Optional for nixpkgs builds (nixpkgs' rustc and cargo by default). Portable builds need the
        # targets' standard libraries: rust-overlay's toolchains get them added.
        rustToolchain = (rust-overlay.lib.mkRustBin { } pkgs).stable.latest.minimal;
      };

      common = {
        pname = "hello"; # the Cargo package; also the module name unless extensionName is set
        version = "0.1.0";
        src = ./.;
        cargoLock.lockFile = ./Cargo.lock;
      };
    in
    {
      packages.aarch64-darwin = rec {
        # lib/php/extensions/hello.so, checked by loading it into this PHP.
        hello = rustPhpPlatform.buildRustPhpExtension (common // { php = pkgs.php84; });
        php = pkgs.php84.withExtensions ({ enabled, ... }: enabled ++ [ hello ]);

        # PHP 8.4 ZTS on Linux arm64 with musl, built here.
        hello-musl = rustPhpPlatform.buildRustPhpExtension (common // {
          php = pkgs.php84;
          target = rustPhpPlatform.targets.aarch64-linux-musl;
          zts = true;
        });

        # php_hello-0.1.0_php8.4-arm64-linux-musl-zts.tgz and its .sha256, and SHA256SUMS.
        pie = rustPhpPlatform.mkPieRelease { name = "php_hello-0.1.0"; extensions = [ hello-musl ]; };

        # Every target (Linux and macOS), NTS and ZTS, for PHP 8.4 and 8.5: 24 archives.
        pie-all = rustPhpPlatform.buildPieRelease { args = common; php = [ pkgs.php84 pkgs.php85 ]; };
      };
    };
}
```

### Publishing an extension for Nix users

`lib.mkPhpExtensionsOverlay` makes an overlay that adds extensions to every PHP of nixpkgs (`php`, `php84`, `php85`, …), each built against the PHP that loads it. It adds them to `php.extensions`, which is where nixpkgs keeps its own. An extension's flake can publish it:

```nix
overlays.default = ext-php-rs.lib.mkPhpExtensionsOverlay {
  # buildRustPhpExtension's arguments for each extension, from Cargo.toml and composer.json.
  extensions = [ (ext-php-rs.lib.extensionArgs { root = ./.; }) ];
};
```

`extensions` can also be a function, for more than `buildRustPhpExtension`'s arguments:

```nix
overlays.default = ext-php-rs.lib.mkPhpExtensionsOverlay {
  extensions = { php, rustPhpPlatform, ... }: {
    hello = rustPhpPlatform.buildRustPhpExtension {
      pname = "hello";
      version = "0.1.0";
      src = ./.;
      cargoLock.lockFile = ./Cargo.lock;
      inherit php;
    };
  };
  # Optional: the rustPhpPlatform to build them with, nixpkgs' Rust by default.
  # rustPhpPlatform = pkgs: ext-php-rs.lib.makeRustPhpPlatform { inherit pkgs; rustToolchain = …; };
};
```

With the overlay applied, users load the extension like one of nixpkgs':

- `pkgs.php84.withExtensions ({ enabled, all }: enabled ++ [ all.hello ])`
- devenv: `languages.php.extensions = [ "hello" ];`, with the overlay in `devenv.yaml` (`inputs.<input>.overlays: [ default ]`)

It doesn't rebuild PHP, and several such overlays combine. nixpkgs' own `php.override { packageOverrides = …; }` doesn't reach the wrapped PHP's extensions (`php.extensions`, `withExtensions`'s `all`), so the overlay rebuilds the wrapper from the overridden PHP.

### Overlay

`overlays.default` adds `pkgs.rustPhpPlatform`, with nixpkgs' Rust, and `pkgs.buildRustPhpExtension` (`pkgs.rustPhpPlatform.buildRustPhpExtension`). nixpkgs' Rust has only the build platform's standard library, so portable builds (with a target) need a toolchain that can add targets:

- **rust-overlay's overlay**, applied as well: portable builds use its latest stable toolchain (`pkgs.rust-bin.stable.latest.minimal`, with the target added), and native builds keep nixpkgs' Rust. The template does this:

  ```nix
  pkgs = nixpkgs.legacyPackages.${system}.appendOverlays [
    rust-overlay.overlays.default
    ext-php-rs.overlays.default
  ];
  ```

- **Another toolchain:** `pkgs.rustPhpPlatform.overrideScope (final: prev: { rustToolchain = …; })`, for every build.

### devenv

In `devenv.yaml`:

```yaml
inputs:
  ext-php-rs:
    url: github:sagikazarmark/ext-php-rs.nix
    inputs:
      nixpkgs:
        follows: nixpkgs
```

In `devenv.nix`:

```nix
{ inputs, pkgs, ... }:
{
  imports = [ inputs.ext-php-rs.devenvModules.default ];

  languages.php.enable = true;
  # Its toolchain builds the extensions. Portable builds need each target's standard library:
  # a toolchainFile toolchain gets them added; with `channel`, list them in languages.rust.targets.
  languages.rust = {
    enable = true;
    channel = "stable";
    targets = [
      "x86_64-unknown-linux-gnu" "aarch64-unknown-linux-gnu"
      "x86_64-unknown-linux-musl" "aarch64-unknown-linux-musl"
      "x86_64-apple-darwin" "aarch64-apple-darwin"
    ];
  };

  ext-php-rs.extensions.hello = {
    args = {
      pname = "hello";
      version = "0.1.0";
      src = ./.;
      cargoLock.lockFile = ./Cargo.lock;
    };
    pie = {
      enable = true;
      php = [ pkgs.php84 pkgs.php85 ];
    };
  };
}
```

`devenv build outputs.hello` builds the extension against `languages.php`'s PHP. `devenv build outputs.hello-pie` builds the 24 PIE archives: two PHP minors × NTS and ZTS × x86_64 and arm64 × Linux with glibc, Linux with musl, and macOS.

Module options:

- **`ext-php-rs.extensions.<name>`:**
  - `args`: `buildRustPhpExtension`'s arguments
  - `php`: the PHP to build against
  - `output`: the output's name, or null for no output
  - `package`: the built extension (read-only)
  - `pie.enable`, `pie.php`, `pie.targets`, `pie.threadSafety`, `pie.output`
  - `pie.package`: the archives (read-only)
- **`ext-php-rs.rustToolchain`:** defaults to `languages.rust`'s toolchain.
- **`ext-php-rs.zig`:** defaults to `languages.zig`'s zig when it is enabled, otherwise `pkgs.zig`. It must be a zig from nixpkgs: bindgen uses the libclang of its LLVM, found among its build inputs, and zig-overlay's prebuilt ones (`languages.zig.version`) have none.
- **`ext-php-rs.lib`:** the functions below, for the shell's packages.

## Functions

`makeRustPhpPlatform { pkgs; rustToolchain ? null; zig ? pkgs.zig; }` (or `pkgs.callPackage ./. { … }`) returns a scope with:

- **`buildRustPhpExtension`**, on the scope's `rustPlatform.buildRustPackage`.
  - **Arguments:**
    - `php`, plus `target` (a Rust/Cargo compile target from `targets`, not Nix's `targetPlatform`) and `zts` for a portable build
    - `pname`, `version`, `src`
    - `cargoHash`, `cargoLock` or `cargoDeps`
    - `cargoPackage`, `extensionName` (the PHP module name), `libName` (the cdylib's)
    - `buildRustPackage`'s: `buildType` (`"release"`, or `"debug"`), `buildFeatures`, `buildNoDefaultFeatures`, `buildAndTestSubdir`, `cargoBuildFlags`, … Its tests are off (`doCheck`): they need PHP's embed SAPI.
    - `allowedLibraries`, for a portable build
  - **Without a target:** built the way `buildRustPackage` builds, for the package set's host platform. With `pkgsCross.<platform>.callPackage`, that's another Nix platform, against that platform's PHP.
  - **With a target:** a portable build, which loads in any PHP of that platform: see [below](#how-a-portable-build-works).
  - **Output:** `lib/php/extensions/<extensionName>.so`, and `share/ext-php-rs/bindings.rs`, the Zend API as bindgen generated it. `passthru` has `extensionName`, `phpVersion`, `zts`, `target` and `headers`.
  - **Install check:** without a target, loads the module into `php`. With one, checks that the module needs only the C library (on macOS, the system's libraries and frameworks), no glibc symbol newer than the floor and no newer macOS than the minimum, and loads it into `php` when `php` is a PHP of that platform (OS, CPU, C library and thread safety).
- **`rustPlatform`:** nixpkgs' for nixpkgs' Rust, otherwise `makeRustPlatform` with `rustToolchain`.
- **`macosSdk`:** the macOS SDK macOS targets build with, by default nixpkgs' `apple-sdk.src`.
- **`targets`:** `x86_64-linux-glibc`, `aarch64-linux-glibc`, `x86_64-linux-musl`, `aarch64-linux-musl`, `x86_64-darwin`, `aarch64-darwin`. The flake also has `lib.targets`.
- **`mkTarget { arch; os ? "linux"; libc ? …; glibc ? "2.28"; macos ? "11.0"; }`:** makes other targets (`arch` is `x86_64` or `aarch64`), such as another glibc floor or minimum macOS. The flake also has `lib.mkTarget`.
- **`mkPieRelease { name; extensions; }`:** every archive in one directory, with each one's `.sha256` file and `SHA256SUMS`. `passthru.archives` has each archive.
- **`buildPieRelease { args; php; targets ? <all>; threadSafety ? [ "nts" "zts" ]; name ? "php_<extensionName>-<version>"; }`:** `buildRustPhpExtension`'s `args` built for every combination of `php` (a list), `targets` and `threadSafety`, as one `mkPieRelease`.
- **`extensionArgs { root; workspace ? root; src ? <what the build reads>; … }`:** `buildRustPhpExtension`'s arguments for a project, read from its files. The flake also has `lib.extensionArgs`.
  - `pname` and `version` from `Cargo.toml` (a version inherited from the workspace too), and `libName` from its `[lib] name`
  - `extensionName` from `composer.json`'s `php-ext.extension-name`, which PIE names the archives and the module after; without one, the Cargo package's name, which ext-php-rs names the module after
  - `cargoLock.lockFile`: the workspace's `Cargo.lock`
  - For a crate in a workspace, `root` is the crate's directory and `workspace` the repository's: the version may come from its `[workspace.package]`, and `Cargo.lock` and `composer.json` come from it. The source is then the whole workspace.
  - `src`: `Cargo.toml`, `Cargo.lock`, `src/`, and `build.rs` and `.cargo/` where they exist, so changing tests, CI or docs rebuilds nothing. Pass `src` for another layout (a workspace, or files the code includes).
  - Other arguments are passed through and override what is read.
- **`runPhpTests { php; extensions ? [ ]; src; flags ? [ ]; }`:** runs the `.phpt` files in `src` ([PHP's test format](https://php.github.io/php-src/miscellaneous/writing-tests.html)) with PHP's `run-tests.php`, with `extensions` loaded through `php.withExtensions`. It fails with each failing test's diff, and when `src` has no `.phpt` files.
- **`mkShell { php; toolchain ? <the scope's>; … }`:** `mkShell` for `cargo build` against `php`, with its `php-config` and the libclang bindgen needs. A module that `cargo build` builds on macOS needs `-undefined dynamic_lookup`: put it in `.cargo/config.toml`, as the template does.
- **`mkPieArchive`, `pieAssetName`, `mkPhpHeaders { php; target; zts; }`:** the parts used along the way.

The flake's `lib.mkPhpExtensionsOverlay { extensions; rustPhpPlatform ? …; }` (`extensions`: a list of `buildRustPhpExtension`'s arguments, or a function) is described [above](#publishing-an-extension-for-nix-users).

Builds set the rustflags an ext-php-rs module needs (`-undefined dynamic_lookup` on macOS, no static C library on musl), so a project needs no `.cargo/config.toml` for them. A `.cargo/config.toml` of its own still applies.

## How a portable build works

ext-php-rs's build script runs `$PHP -i` and `$PHP_CONFIG --includes`. It reads four `php -i` entries (version, PHP API, thread safety, debug build) and the include path, then runs bindgen over the headers. It never runs the target's PHP, so:

- **Headers** (`lib/php-headers.nix`): nixpkgs' PHP source, run through `./configure` for the target with `zig cc` as the cross compiler, then `make install-headers` and the `php-config` configure writes. Nothing is compiled, and it takes about a minute. A build without a target uses nixpkgs' PHP itself: its headers and `php-config` (its dev output), and its `php`.
  - **Why configured headers:** they must come from a PHP configured for the target platform and thread safety, because `php_config.h` changes the layout of structs ext-php-rs binds. A ZTS build on Linux adds timer fields to the executor globals, and the core globals differ between Linux and macOS. With the wrong headers, a module builds and then misreads PHP's memory.
  - **Always a cross configure**, so the result doesn't depend on the build platform.
  - **Presets.** Two checks need to run a program, and are preset to what PHP's own build finds:
    - `php_cv_have_stack_limit=yes`: otherwise `ZEND_CHECK_STACK_LIMIT` and the executor globals' call stack fields go missing.
    - `php_cv_have_global_register_vars=yes` on Linux, where PHP is built with gcc: otherwise the Zend VM kind changes, and with it PHP 8.5's `zend_vm_opcode_handler_t`. PHP on macOS is built with clang, which has none, like zig.
- **Stub** (`lib/write-php-stub.sh`): a `bin/php` script that answers `php -i` from those headers. A `pkgsCross` build, whose PHP can't run on the build platform either, uses one with that PHP's own headers.
- **Compiling and linking** use `cargo zigbuild`, against the target's glibc floor (default 2.28), musl, or minimum macOS (default 11.0). bindgen uses the libclang of zig's own LLVM, because zig's builtin headers (`arm_neon.h`, …) only parse with the same clang version. The scope takes it from zig's build inputs, so any zig works.
- **C dependencies** of `-sys` crates (zstd-sys, libz-sys, openssl-sys, …) are built from their vendored sources by zig and linked statically. buildRustPackage tells those crates to link the system's libraries through pkg-config instead, which in a portable build would be Nix's, for the build platform: a portable build sets `dontCargoUseSystemLibs` (a build without a target keeps nixpkgs' behaviour, and needs the libraries and `pkg-config` as inputs). A build script that compiles a program and runs it, for a glibc target that is the build platform's own (aws-lc-sys's compiler check), gets Nix's dynamic loader through `LDFLAGS`: the Nix sandbox has no `/lib64/ld-linux-*.so`, which zig gives glibc executables.
- **macOS** targets build with nixpkgs' macOS SDK (the scope's `macosSdk`, Apple's Command Line Tools SDK as nixpkgs fetches it), given to zig and bindgen as `SDKROOT`, so a macOS module builds the same way on Linux, frameworks included. The module's install name is `<extensionName>.so`, not the build's path. It takes cargo-zigbuild 0.24 or later, which keeps rustc's `-exported_symbols_list` file with the flag for zig 0.16 and later ([#479](https://github.com/rust-cross/cargo-zigbuild/issues/479)), and gives zig the minimum macOS from `MACOSX_DEPLOYMENT_TARGET` ([#488](https://github.com/rust-cross/cargo-zigbuild/issues/488)). nixpkgs has 0.23.4, so the scope builds 0.24.1 until it catches up.
- **Checking:** a module built for another platform can't be loaded where it's built, so its install check reads it instead: the shared libraries it needs, its glibc symbol versions or its minimum macOS. Where the build machine's PHP is of the module's platform (the x86_64 glibc NTS ones on an x86_64 Linux, the arm64 macOS NTS ones on a Mac), it loads it too. CI loads the others on a machine of their OS and CPU: in the official images, and on macOS into setup-php's PHP.

**Verified** with [restate-php](https://github.com/restate-php/restate)'s extension (ext-php-rs 0.16.4, PHP 8.4.27 and 8.5.12 from nixpkgs), across all 16 combinations of PHP 8.4 and 8.5, NTS and ZTS, x86_64 and arm64, and glibc and musl:

- The generated bindings are identical to those generated from the official `php` Docker images' own headers.
- Every module loads into the matching official image.
- Debug builds pass that extension's test suite there.

For macOS, the example's bindings for arm64 NTS are those generated from nixpkgs' PHP on macOS (configured natively), apart from the parameter names of two function pointers in the SDK's `FILE`.

To check another PHP release, compare `share/ext-php-rs/bindings.rs` with bindings generated from the image's `/usr/local/include/php`.

## Caveats

- ext-php-rs passes the macOS SDK to bindgen whenever its build script runs on macOS, even for another target. Portable builds on macOS put an `xcrun` that fails first on `PATH`.
- Panic messages contain source paths, and Nix's build directory has a random name on macOS. Builds remap it to `/build`, so each build platform reproduces its own builds. A module built on macOS and the same module built on Linux still differ.
- zig-linked musl modules list `libc.so` as their C library (musl's loader resolves it to itself) and contain their own unwinder (no `libgcc_s`).
- Modules are built against nixpkgs' PHP patch release. A module loads into later patch releases of the same minor, and into earlier ones as long as it uses no function added since. Debug builds reference every bound function, so they need at least that patch release.
- Until nixpkgs has cargo-zigbuild 0.24, the scope's is built from source, once.
- PIE archives are for Linux and macOS; PIE on Windows wants DLLs.
- Portable builds run bindgen with zig's libclang, which old bindgen releases may misread: [kcs/lopdf](https://packagist.org/packages/kcs/lopdf) 0.1.0 (ext-php-rs 0.13.1, bindgen 0.68.1) gets opaque Zend structs with zig 0.17's libclang 22, though it builds natively with nixpkgs' libclang 21.

## Development

The flake has the library only; its one input is nixpkgs. The tests and the development environment are devenv's (`devenv.nix`). It takes this flake as an input (`devenv.yaml`, `git+file:.`, so git-tracked files only, as with flakes) and follows its nixpkgs, so what CI builds and caches is what projects using the flake build.

- **Layout:**
  - `lib/`: the library (`lib/default.nix` is the scope; the root `default.nix` imports it)
  - `modules/devenv.nix`: the devenv module
  - `templates/default/`: the project template, which is also the example extension (`hello_world(string $name): string`) the tests build
  - `tests/`:
    - `default.nix`: every check, and the archives CI loads; `checks.nix` has the library's own
    - `example.nix`: the example's builds
    - `real-world.nix`: the real-world extensions, and `real-world/`: `.phpt` tests for those whose releases have none
    - `fixtures/features/`: a crate whose output shows the Cargo features it was built with
    - the scripts that load archives (`load.sh`, `load-macos.sh`) and install them with PIE (`pie.sh`, `pie-api.py`), which share `lib.sh`

- **`devenv shell`** has the lint tools, a Rust toolchain, and a PHP 8.4 with the example extension, built through the devenv module.
- **`devenv build`** builds every check, and the archives CI loads. `devenv build outputs.checks.<name>` builds one. The checks:
  - the example extension, built natively for PHP 8.4, 8.5 and 8.6, with a rust-overlay toolchain and with nixpkgs' Rust through the overlay
  - the example's `.phpt` tests (the template's, run with `runPhpTests`) through `php.withExtensions`, and through `mkPhpExtensionsOverlay` by name
  - the overlay: native builds with nixpkgs' Rust, portable builds refused without rust-overlay's overlay and built with its toolchain alongside it
  - on x86_64 Linux: the example built with `pkgsCross` for aarch64 Linux, loaded into that platform's PHP with qemu
  - its 36 PIE archives (PHP 8.4, 8.5 and 8.6)
  - `buildRustPackage`'s build options (`buildAndTestSubdir`, `buildType`, `buildNoDefaultFeatures`, `buildFeatures`) in a native and a portable build, each loaded into PHP: a portable build passes them to `cargo zigbuild` itself
  - the devenv module's outputs
  - `extensionArgs` on the template and fixtures (`tests/fixtures/extension-args`: a workspace version, a `[lib] name`, a `composer.json`; `tests/fixtures/workspace`: a crate in a workspace)
  - the target definitions and the arguments each kind of build refuses (`lib.runTests`: a failing check names every test that fails)
  - the template's flake, with this flake as its `ext-php-rs` input: its checks (its `.phpt` tests, with the extension through its overlay, in PHP 8.4, 8.5 and 8.6), its package and shell, and the evaluation of its 36 PIE archives
  - real extensions (`tests/real-world.nix`), ext-php-rs extensions among Packagist's PIE packages, pinned at their releases. Each one is built natively for PHP 8.4, tested with `.phpt` files through `php.withExtensions`, and cross-compiled for x86_64 glibc NTS, aarch64 musl ZTS and aarch64 macOS NTS. They bring build setups this flake must cope with: their own build scripts, C and assembly dependencies (ring, zstd), a Cargo workspace, and `.cargo/config.toml` linker settings.

    | Extension | Package | ext-php-rs | Tests |
    | --- | --- | --- | --- |
    | `anydoc` | [hosmelq/ext-anydoc](https://packagist.org/packages/hosmelq/ext-anydoc) 1.0.0 | 0.16.5 | ours (`tests/real-world/anydoc`): format detection, from its repository's tests, which its release archive leaves out |
    | `arrow` | [flow-php/arrow-ext](https://packagist.org/packages/flow-php/arrow-ext) 0.48.0 | 0.16.3 | ours (`tests/real-world/arrow`): three of its tests (the extension, its `phpinfo()` and version), which its release archive leaves out; the rest need flow-php's monorepo |
    | `grpc` | [bsn4/grpc](https://packagist.org/packages/bsn4/grpc) 0.4.0 | 0.15.15 | ours (`tests/real-world/grpc`): an insecure `Grpc\Channel` and its target |
    | `mjml` | [kcs/mjml](https://packagist.org/packages/kcs/mjml) 1.2.2 | 0.16.2 | its own `tests/`, but one that fetches a template from GitHub |
    | `rabbitmq` | [jaapieaapie1/rabbitmq-ext](https://packagist.org/packages/jaapieaapie1/rabbitmq-ext) 1.0.0 | 0.15.8 | ours (`tests/real-world/rabbitmq`): its exceptions, and a refused connection; its own (Pest) need a RabbitMQ server |
- **`devenv build outputs.load-tests`** collects every portable archive (the example's and the real extensions'), each extension's `.phpt` tests (`tests/<name>/`), PIE (1.5.5), and PHP's `run-tests.php`. With it:
  - **`tests/load.sh <dir> <php minor> <nts|zts> <x86_64|arm64> <glibc|musl>`** loads that PHP's Linux archives into its official image and runs their `.phpt` tests there with the image's `run-tests.php`, the module loaded alone (`-n`) (Docker; Docker Desktop emulates the other CPU).
  - **`tests/pie.sh <dir> <php minor> <nts|zts> <x86_64|arm64> <glibc|musl>`** installs them with `pie install` instead, then runs the `.phpt` tests with the php.ini PIE leaves. PIE looks for pre-packaged binaries through GitHub's API: `tests/pie-api.py` stands in for it, with a certificate the image trusts.
  - **`tests/load-macos.sh <dir>`** loads the macOS archives for the PHP on `PATH` into it and runs their `.phpt` tests, with that PHP's `run-tests.php` (or the one in `<dir>`).
- **`devenv test`** runs `lint` (formatting, actionlint, shellcheck, statix and deadnix), then runs the example's `.phpt` tests with the shell's PHP. **`nix fmt`** formats the Nix files.
- **CI** (`.github/workflows/ci.yaml`):
  - runs `devenv build` on Linux x86_64 and arm64 and on macOS, with ext-php-rs.cachix.org: pushes from `main`, pulls everywhere
  - loads every Linux archive into its official image on a runner of its CPU, and installs it there with PIE
  - loads every macOS archive (built on Linux) into setup-php's PHP on an arm64 or Intel Mac
  - runs `nix flake check` and `devenv test`

## License

The project is licensed under the [MIT License](LICENSE).

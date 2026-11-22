# Contributing

The flake has the library only, and its one input is nixpkgs. The tests and the development
environment are devenv's ([`devenv.nix`](devenv.nix)). devenv takes this flake as an input
(`git+file:.` in [`devenv.yaml`](devenv.yaml), so git-tracked files only, as with flakes) and
follows its nixpkgs, so what CI builds and caches is what projects using the flake build.

## Layout

- `lib/`: the library. `lib/default.nix` is the `rustPhpPlatform` scope (the root `default.nix`
  imports it), and `lib/flake-lib.nix` the flake's `lib`.
- `modules/devenv.nix`: the devenv module.
- `templates/default/`: the project template, which is also the example extension
  (`hello_world(string $name): string`) the tests build.
- `docs/`: the documentation. `functions.md` and `devenv-options.md` are generated
  (`docs/generate.nix`).
- `tests/`:
  - `default.nix`: every check, and the archives CI loads; `checks.nix` has the library's own.
  - `example.nix`: the example's builds.
  - `real-world.nix`: the real-world extensions, and `real-world/`: `.phpt` tests for those whose
    releases have none.
  - `fixtures/features/`: a crate whose output shows the Cargo features it was built with.
  - The scripts that load macOS archives (`load-macos.sh`) and install Linux ones with PIE
    (`pie.sh`, `pie-api.py`). They share `lib/load-lib.sh` with `lib/load-pie-archives.sh`
    (`loadPieArchives`), which loads Linux archives.

## Commands

- **`devenv shell`** has the lint tools, a Rust toolchain, and a PHP 8.4 with the example
  extension, built through the devenv module.
- **`devenv build`** builds every check, and the archives CI loads. `devenv build
  outputs.checks.<name>` builds one check.
- **`devenv test`** runs `lint` (formatting, actionlint, shellcheck, statix and deadnix), then the
  example's `.phpt` tests with the shell's PHP.
- **`nix fmt`** formats the Nix files.
- **`update-docs`** regenerates `docs/functions.md` and `docs/devenv-options.md`.

## Documentation

The function reference is generated with [nixdoc](https://github.com/nix-community/nixdoc) from
the [RFC 145](https://github.com/NixOS/rfcs/blob/master/rfcs/0145-doc-strings.md) doc comments
(`/** … */`) on the attributes in `lib/default.nix` and `lib/flake-lib.nix`. The devenv options
page is generated from the module's option descriptions.

After changing either, run `update-docs` and commit the result: the `docs` check fails when
`docs/` is out of date.

## Checks

- The example extension, built natively for PHP 8.4, 8.5 and 8.6, with a rust-overlay toolchain
  and with nixpkgs' Rust through the overlay.
- The example's `.phpt` tests (the template's, run with `runPhpTests`) through
  `php.withExtensions`, and through `mkPhpExtensionsOverlay` by name.
- `mkPhpExtensionsOverlay` with a PHP that's overridden after it (FrankenPHP's ZTS PHP),
  which must rebuild nixpkgs' extensions and the overlay's for itself and start without a warning.
- `runFpmTests` failing when a child of FPM crashes, though FPM replaces it and the test's
  requests succeed.
- The overlay: native builds with nixpkgs' Rust, portable builds refused without rust-overlay's
  overlay and built with its toolchain alongside it.
- On x86_64 Linux: the example built with `pkgsCross` for aarch64 Linux, loaded into that
  platform's PHP with qemu.
- The example's 36 PIE archives (PHP 8.4, 8.5 and 8.6).
- `buildRustPackage`'s build options (`buildAndTestSubdir`, `buildType`, `buildNoDefaultFeatures`,
  `buildFeatures`) in a native and a portable build, each loaded into PHP: a portable build passes
  them to `cargo zigbuild` itself.
- The devenv module's outputs.
- `extensionArgs` on the template and fixtures (`tests/fixtures/extension-args`: a workspace
  version, a `[lib] name`, a `composer.json`; `tests/fixtures/workspace`: a crate in a
  workspace).
- The target definitions and the arguments each kind of build refuses (`lib.runTests`: a failing
  check names every test that fails).
- The template's flake, with this flake as its `ext-php-rs` input: its checks (its `.phpt` tests,
  with the extension through its overlay, in PHP 8.4, 8.5 and 8.6 and with FrankenPHP's ZTS PHP,
  its FrankenPHP worker test with `runFrankenphpTests`, and its PHP-FPM test with
  `runFpmTests`), its package and shell, and
  the evaluation of its 36 PIE archives.
- The generated docs are up to date.
- Real extensions ([`tests/real-world.nix`](tests/real-world.nix)), described below.

### Real-world extensions

ext-php-rs extensions among Packagist's PIE packages, pinned at their releases. Each one is built
natively for PHP 8.4, tested with `.phpt` files through `php.withExtensions`, and cross-compiled
for x86_64 glibc NTS, aarch64 musl ZTS and aarch64 macOS NTS. They bring build setups this flake
must cope with: their own build scripts, C and assembly dependencies (ring, zstd), a Cargo
workspace, and `.cargo/config.toml` linker settings.

| Extension | Package | ext-php-rs | Tests |
| --- | --- | --- | --- |
| `anydoc` | [hosmelq/ext-anydoc](https://packagist.org/packages/hosmelq/ext-anydoc) 1.0.0 | 0.16.5 | ours (`tests/real-world/anydoc`): format detection, from its repository's tests, which its release archive leaves out |
| `arrow` | [flow-php/arrow-ext](https://packagist.org/packages/flow-php/arrow-ext) 0.48.0 | 0.16.3 | ours (`tests/real-world/arrow`): three of its tests (the extension, its `phpinfo()` and version), which its release archive leaves out; the rest need flow-php's monorepo |
| `grpc` | [bsn4/grpc](https://packagist.org/packages/bsn4/grpc) 0.4.0 | 0.15.15 | ours (`tests/real-world/grpc`): an insecure `Grpc\Channel` and its target |
| `mjml` | [kcs/mjml](https://packagist.org/packages/kcs/mjml) 1.2.2 | 0.16.2 | its own `tests/`, but one that fetches a template from GitHub |
| `rabbitmq` | [jaapieaapie1/rabbitmq-ext](https://packagist.org/packages/jaapieaapie1/rabbitmq-ext) 1.0.0 | 0.15.8 | ours (`tests/real-world/rabbitmq`): its exceptions, and a refused connection; its own (Pest) need a RabbitMQ server |

## Loading archives on other machines

`devenv build outputs.load-tests` collects every portable archive (the example's and the real
extensions'), each extension's `.phpt` tests (`tests/<name>/`), PIE (1.5.5), and PHP's
`run-tests.php`. With it:

- **`lib/load-pie-archives.sh --php <minor> --ts <nts|zts> --arch <x86_64|arm64> --libc
  <glibc|musl> <dir> <dir>/tests`** (`loadPieArchives`, which projects use too) loads that PHP's
  Linux archives into its official image and runs their `.phpt` tests there with the image's
  `run-tests.php`, the module loaded alone (`-n`). It needs Docker (or `DOCKER=podman`); Docker
  Desktop emulates the other CPU.
- **`tests/pie.sh <dir> <php minor> <nts|zts> <x86_64|arm64> <glibc|musl>`** installs them with
  `pie install` instead, then runs the `.phpt` tests with the php.ini PIE leaves. PIE looks for
  pre-packaged binaries through GitHub's API: `tests/pie-api.py` stands in for it, with a
  certificate the image trusts.
- **`tests/load-macos.sh <dir>`** loads the macOS archives for the PHP on `PATH` into it and runs
  their `.phpt` tests, with that PHP's `run-tests.php` (or the one in `<dir>`).

## CI

[`.github/workflows/ci.yaml`](.github/workflows/ci.yaml):

- runs `devenv build` on Linux x86_64 and arm64 and on macOS, with ext-php-rs.cachix.org: it
  pushes from `main`, and pulls everywhere
- loads every Linux archive into its official image on a runner of its CPU, and installs it there
  with PIE
- loads every macOS archive (built on Linux) into setup-php's PHP on an arm64 or Intel Mac
- runs `nix flake check` and `devenv test`

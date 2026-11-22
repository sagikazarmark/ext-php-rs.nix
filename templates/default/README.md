# hello

A PHP extension written in Rust with [ext-php-rs](https://github.com/extphprs/ext-php-rs), built with [ext-php-rs.nix](https://github.com/sagikazarmark/ext-php-rs.nix).

To rename it: `name` in `Cargo.toml` (then `cargo generate-lockfile`), `name` and `php-ext.extension-name` in `composer.json`, and `--EXTENSIONS--` in `tests/*.phpt`. The flake reads the version from `Cargo.toml` and the module's name from `composer.json`.

## Development

- `nix develop`, then `cargo build`: against nixpkgs' default PHP.
- `nix flake check`: runs `tests/*.phpt` ([PHP's test format](https://php.github.io/php-src/miscellaneous/writing-tests.html)) with PHP 8.4, 8.5 and 8.6, with the extension loaded.
- `nix run .#php -- -r 'echo hello_world("Nix");'`: nixpkgs' default PHP with the extension.
- `nix build .#pie`: the release archives.

`cachix use ext-php-rs` (or accepting the substituter when Nix asks) fetches the PHP headers and cargo-zigbuild that portable builds use, instead of building them. The flake takes nixpkgs from ext-php-rs.nix for that: the cache only has what that nixpkgs builds.

## Using it

### With Nix

The flake's `overlays.default` adds the extension to every PHP of nixpkgs:

```nix
pkgs.php.withExtensions ({ enabled, all }: enabled ++ [ all.hello ])
```

With devenv, add the flake to `devenv.yaml` with the overlay:

```yaml
inputs:
  hello:
    url: github:acme/hello
    overlays: [default]
```

and in `devenv.nix`: `languages.php.extensions = [ "hello" ];`.

### With PIE

```shell
pie install acme/hello
```

## Customizing

The flake uses ext-php-rs.nix's defaults wherever it can. Each change below goes where the flake already has the thing it changes. [ext-php-rs.nix's function reference](https://github.com/sagikazarmark/ext-php-rs.nix/blob/main/docs/functions.md) documents every function and argument.

### PHP versions

The release archives are built for the PHP versions in `pie`'s `php` list (nixpkgs has `php81` to `php86`). The tests run with those in `checks`' list. Keep `require.php` in `composer.json` in line with both:

```nix
pie = pkgs.rustPhpPlatform.buildPieRelease {
  inherit args;
  php = [ pkgs.php83 pkgs.php84 pkgs.php85 pkgs.php86 ];
};
```

### Targets and thread safety

By default `pie` builds every target (x86_64 and arm64; Linux with glibc, Linux with musl, and macOS) both NTS and ZTS. To build fewer:

```nix
pie = pkgs.rustPhpPlatform.buildPieRelease {
  inherit args;
  php = [ pkgs.php84 pkgs.php85 pkgs.php86 ];
  targets = with pkgs.rustPhpPlatform.targets; [
    x86_64-linux-glibc
    aarch64-linux-glibc
    aarch64-darwin
  ];
  threadSafety = [ "nts" ];
};
```

The targets are `x86_64-linux-glibc`, `aarch64-linux-glibc`, `x86_64-linux-musl`, `aarch64-linux-musl`, `x86_64-darwin` and `aarch64-darwin`.

### glibc floor and minimum macOS

Linux glibc modules load with glibc 2.28 or later, and macOS modules on macOS 11.0 or later. `mkTarget` makes a target with another floor:

```nix
targets = with pkgs.rustPhpPlatform; [
  (mkTarget { arch = "x86_64"; libc = "glibc"; glibc = "2.31"; })
  (mkTarget { arch = "aarch64"; os = "darwin"; macos = "13.0"; })
  targets.aarch64-linux-musl
];
```

PIE names archives by OS, CPU and C library only. Each combination can appear once, so a custom target replaces the default one with the same OS, CPU and C library.

### Cargo features and other build options

`extensionArgs` passes any other argument to the build, every build of it (the overlay, `pie`, `checks`):

```nix
args = ext-php-rs.lib.extensionArgs {
  root = ./.;
  buildNoDefaultFeatures = true;
  buildFeatures = [ "tokio" ];
};
```

It also takes the rest of `buildRustPackage`'s arguments (`cargoBuildFlags`, `buildType`, …). A build of `pie` alone gets its own: `args = args // { … };`.

### A pinned Rust toolchain

Portable builds use rust-overlay's latest stable toolchain, and the overlay's builds use nixpkgs' Rust. To build `pie` with the toolchain in `rust-toolchain.toml` instead:

```toml
[toolchain]
channel = "1.95.0"
profile = "minimal"
```

```nix
pie =
  (pkgs.rustPhpPlatform.overrideScope (_: _: {
    rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
  })).buildPieRelease
    {
      inherit args;
      php = [ pkgs.php84 pkgs.php85 pkgs.php86 ];
    };
```

Each target's standard library is added to it. For the overlay's builds, give `mkPhpExtensionsOverlay` the same toolchain:

```nix
overlays.default = ext-php-rs.lib.mkPhpExtensionsOverlay {
  extensions = [ args ];
  rustPhpPlatform =
    pkgs:
    ext-php-rs.lib.makeRustPhpPlatform {
      inherit pkgs;
      rustToolchain = (rust-overlay.lib.mkRustBin { } pkgs).fromRustupToolchainFile ./rust-toolchain.toml;
    };
};
```

For the dev shell, use `toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;`. List `rust-src` and `rust-analyzer` in the file's `components` to keep rust-analyzer working.

### A Cargo workspace

For an extension that is one crate of a workspace, `root` is the crate's directory and `workspace` the repository's. The version may come from `[workspace.package]`, and `Cargo.lock` and `composer.json` come from the repository's directory:

```nix
args = ext-php-rs.lib.extensionArgs {
  root = ./crates/hello;
  workspace = ./.;
};
```

The source is then the whole workspace. To rebuild less often, pass a narrower `src`:

```nix
src = lib.fileset.toSource {
  root = ./.;
  fileset = lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./crates ];
};
```

## Releasing

Push a tag that is `Cargo.toml`'s version (`1.2.0`, not `v1.2.0`: PIE looks for archives named with the tag). `.github/workflows/release.yaml` builds the archives and publishes them as the release's assets, then Packagist picks up the tag.

CI and releases use ext-php-rs.cachix.org. For a cache of this project's own builds, set the repository variable `CACHIX_CACHE` to its name and the secret `CACHIX_AUTH_TOKEN`.

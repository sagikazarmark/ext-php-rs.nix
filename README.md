# ext-php-rs.nix

[![CI](https://img.shields.io/github/actions/workflow/status/sagikazarmark/ext-php-rs.nix/ci.yaml?style=flat-square)](https://github.com/sagikazarmark/ext-php-rs.nix/actions/workflows/ci.yaml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/sagikazarmark/ext-php-rs.nix/badge?style=flat-square)](https://securityscorecards.dev/viewer/?uri=github.com/sagikazarmark/ext-php-rs.nix)

Build PHP extensions written in Rust with [ext-php-rs](https://github.com/extphprs/ext-php-rs), using Nix.

- **For Nix users:** build an extension against any PHP in nixpkgs, and publish it as an overlay
  that users load like any of nixpkgs' own extensions.
- **For everyone else:** cross-compile portable modules for Linux and macOS (x86_64 or aarch64;
  glibc, musl or macOS; NTS or ZTS) from any machine. They load in any PHP of that kind: the
  official Docker images, distribution packages, Homebrew.
- **For [PIE](https://github.com/php/pie):** package those modules as the prebuilt archives
  `pie install` looks for on a GitHub release.

It comes as a flake library, an overlay, and a [devenv](https://devenv.sh) module.

## Quick start

```shell
nix flake init -t github:sagikazarmark/ext-php-rs.nix
```

This creates an extension project with:

- an overlay that adds the extension to every PHP in nixpkgs
- PIE archives for PHP 8.4, 8.5 and 8.6 on every target, and a release workflow that publishes
  them when you push a tag
- `.phpt` tests and a FrankenPHP worker test that `nix flake check` runs
- a dev shell for `cargo build`, clippy and rust-analyzer

The [template's README](templates/default/README.md) covers renaming, customizing and releasing.

### Binary cache

Portable builds need PHP headers configured for each target and a recent cargo-zigbuild. CI
pushes both to [ext-php-rs.cachix.org](https://ext-php-rs.cachix.org):

```shell
cachix use ext-php-rs
```

The cache only has what this flake's nixpkgs builds, so take nixpkgs from this flake
(`nixpkgs.follows = "ext-php-rs/nixpkgs"`, as the template does), not the other way around.

## Usage

### Building extensions

```nix
{
  inputs = {
    ext-php-rs.url = "github:sagikazarmark/ext-php-rs.nix";
    nixpkgs.follows = "ext-php-rs/nixpkgs"; # for the binary cache
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, rust-overlay, ext-php-rs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      rustPhpPlatform = ext-php-rs.lib.makeRustPhpPlatform {
        inherit pkgs;
        # Portable builds need a toolchain that can add each target's standard library.
        rustToolchain = (rust-overlay.lib.mkRustBin { } pkgs).stable.latest.minimal;
      };

      # pname, version, src, … from Cargo.toml and composer.json.
      args = ext-php-rs.lib.extensionArgs { root = ./.; };
    in
    {
      packages.x86_64-linux = {
        # For nixpkgs' PHP: php84.withExtensions ({ enabled, ... }: enabled ++ [ hello ])
        hello = rustPhpPlatform.buildRustPhpExtension (args // { php = pkgs.php84; });

        # A portable module for PHP 8.4 ZTS on Linux arm64 with musl.
        hello-musl = rustPhpPlatform.buildRustPhpExtension (args // {
          php = pkgs.php84;
          target = rustPhpPlatform.targets.aarch64-linux-musl;
          zts = true;
        });

        # PIE archives for every target, NTS and ZTS, for PHP 8.4 and 8.5: 24 archives.
        pie = rustPhpPlatform.buildPieRelease {
          inherit args;
          php = [ pkgs.php84 pkgs.php85 ];
        };
      };
    };
}
```

See [the function reference](docs/functions.md) for every function and argument.

### Publishing an extension for Nix users

`mkPhpExtensionsOverlay` makes an overlay that adds extensions to every PHP in nixpkgs (`php`,
`php84`, `php85`, …), each built against the PHP that loads it:

```nix
overlays.default = ext-php-rs.lib.mkPhpExtensionsOverlay {
  extensions = [ (ext-php-rs.lib.extensionArgs { root = ./.; }) ];
};
```

With the overlay applied, users load the extension like one of nixpkgs':

```nix
pkgs.php84.withExtensions ({ enabled, all }: enabled ++ [ all.hello ])
```

In devenv, add the flake to `devenv.yaml` with `overlays: [ default ]`, then use
`languages.php.extensions = [ "hello" ];`.

### Testing

These three run in the Nix sandbox as checks, without Docker:

- `runPhpTests` runs `.phpt` tests with PHP's `run-tests.php`, with the extensions loaded.
- `runFrankenphpTests` starts a [FrankenPHP](https://frankenphp.dev) and runs a test script
  against it. The script can send requests, send them concurrently, and restart workers. These
  cover what CLI tests can't: threads, a worker that stays loaded across requests, and module
  restarts.
- `runFpmTests` does the same with PHP-FPM behind Caddy. Its script can also reload FPM. This
  covers forking: FPM's master starts the extension (`MINIT`), then forks the children that
  handle requests, which don't have the threads it started. Each child handles many requests,
  then shuts the module down itself. The check fails if a child crashes, even though FPM
  replaces it and later requests succeed.

`loadPieArchives` is a command for the archives users install: it loads a PIE release's Linux
archives into PHP's official Docker images (`php:8.4-zts-alpine`, …) and runs the `.phpt` tests
there (`load-pie-archives [--php 8.4] [--ts zts] [--libc musl] <archives> <tests>`).

FrankenPHP's PHP is thread-safe (ZTS), so extensions must be built for it. With the extension's
overlay applied, nixpkgs' `frankenphp` rebuilds them itself:

```nix
checks.frankenphp = rustPhpPlatform.runFrankenphpTests {
  frankenphp = pkgs.frankenphp.override {
    php = pkgs.php.withExtensions ({ enabled, all }: enabled ++ [ all.hello ]);
  };
  src = ./tests/frankenphp; # index.php: the worker
  script = ''
    expect "/?name=Nix" "Hello, Nix!"
    restart_workers
    expect "/?name=Nix" "Hello, Nix!"
    concurrently 20 "/?name=Nix"
  '';
};
```

FPM forks every child from the same master. To test children that FPM replaces, set
`maxRequests` so each one exits after that many requests:

```nix
checks.fpm = rustPhpPlatform.runFpmTests {
  php = pkgs.php.withExtensions ({ enabled, all }: enabled ++ [ all.hello ]);
  src = ./tests/fpm; # index.php: echo hello_world($_GET["name"]);
  maxRequests = 5;
  script = ''
    expect "/?name=Nix" "Hello, Nix!"
    concurrently 20 "/?name=Nix"
    reload
    expect "/?name=Nix" "Hello, Nix!"
  '';
};
```

### Overlay

`overlays.default` adds `pkgs.rustPhpPlatform` (using nixpkgs' Rust) and
`pkgs.buildRustPhpExtension`. nixpkgs' Rust can't build for other targets, so for portable builds
apply rust-overlay's overlay as well; its latest stable toolchain is then used for them:

```nix
pkgs = nixpkgs.legacyPackages.${system}.appendOverlays [
  rust-overlay.overlays.default
  ext-php-rs.overlays.default
];
```

For another toolchain, use `pkgs.rustPhpPlatform.overrideScope (final: prev: { rustToolchain = …; })`.

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
  languages.rust = {
    enable = true;
    channel = "stable";
    # Portable builds need each target's standard library.
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

- `devenv build outputs.hello` builds the extension against `languages.php`'s PHP.
- `devenv build outputs.hello-pie` builds the 24 PIE archives.

See [the module options](docs/devenv-options.md).

## Documentation

- [Functions](docs/functions.md): every function and its arguments
- [devenv module options](docs/devenv-options.md)
- [How portable builds work](docs/portable-builds.md), how they're verified, and their caveats

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the layout, the tests and CI.

## License

The project is licensed under the [MIT License](LICENSE).

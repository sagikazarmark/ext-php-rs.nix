# devenv module options

<!-- Generated from modules/devenv.nix: run `update-docs` (devenv) after changing it. -->

The options of [`devenvModules.default`](../modules/devenv.nix).

## `ext-php-rs.extensions`

Extensions to build, by name.

**Type:** attribute set of (submodule)

**Default:** `{ }`

## `ext-php-rs.extensions.<name>.args`

Arguments of `buildRustPhpExtension` that every build of the extension shares: `pname`,
`version`, `src`, `cargoHash` or `cargoLock`, and optionally `cargoPackage`,
`extensionName` and `buildRustPackage`'s arguments (`buildType`, `buildFeatures`,
`cargoBuildFlags`, …).

**Type:** lazy attribute set of raw value

**Default:** `{ }`

**Example:**

```nix
{
  pname = "hello";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
}
```

## `ext-php-rs.extensions.<name>.output`

The output that builds the extension against `php` (`devenv build outputs.<output>`); null for none.

**Type:** null or string

**Default:** `"‹name›"`

## `ext-php-rs.extensions.<name>.package`

The extension built against `php`: `lib/php/extensions/<extensionName>.so`.

**Type:** package (read-only)

## `ext-php-rs.extensions.<name>.php`

The PHP the extension is built against, and loaded into to check it.

**Type:** package

**Default:** `config.languages.php.package`

## `ext-php-rs.extensions.<name>.pie.enable`

Whether to enable the extension's prebuilt binaries for PIE, cross-compiled for Linux and macOS.

**Type:** boolean

**Default:** `false`

**Example:** `true`

## `ext-php-rs.extensions.<name>.pie.output`

The output that builds the archives, their `.sha256` files and `SHA256SUMS`; null for none.

**Type:** null or string

**Default:** `"‹name›-pie"`

## `ext-php-rs.extensions.<name>.pie.package`

Every archive in one directory (`buildPieRelease`); `passthru.archives` has each one.

**Type:** package (read-only)

## `ext-php-rs.extensions.<name>.pie.php`

The PHP versions to build for: one archive per PHP minor, target and thread safety.

**Type:** list of package

**Default:** `[ config.languages.php.package ]`

**Example:** `[ pkgs.php84 pkgs.php85 ]`

## `ext-php-rs.extensions.<name>.pie.targets`

The targets (OS, CPU and C library) to build for.

**Type:** list of (one of "aarch64-darwin", "aarch64-linux-glibc", "aarch64-linux-musl", "x86_64-darwin", "x86_64-linux-glibc", "x86_64-linux-musl")

**Default:**

```nix
[
  "aarch64-darwin"
  "aarch64-linux-glibc"
  "aarch64-linux-musl"
  "x86_64-darwin"
  "x86_64-linux-glibc"
  "x86_64-linux-musl"
]
```

## `ext-php-rs.extensions.<name>.pie.threadSafety`

The thread safety modes to build for.

**Type:** list of (one of "nts", "zts")

**Default:**

```nix
[
  "nts"
  "zts"
]
```

## `ext-php-rs.lib`

The ext-php-rs functions for this shell's packages, `rustToolchain` and `zig`: `buildRustPhpExtension`, `targets`, `mkPieRelease`, ….

**Type:** raw value (read-only)

## `ext-php-rs.rustToolchain`

The Rust toolchain the extensions are built with; null for nixpkgs' rustc and cargo.
Portable builds add their target with `rustToolchain.override { targets = [ … ]; }` where
the toolchain supports it (`languages.rust.toolchainFile`'s does); otherwise it must
already have the targets' standard libraries (`languages.rust.targets`).

**Type:** null or package

**Default:** `config.languages.rust.toolchainPackage, when languages.rust is enabled`

## `ext-php-rs.zig`

The zig that portable builds link with; bindgen uses the libclang of its LLVM, which it
finds among the zig's build inputs. A zig from nixpkgs has it; zig-overlay's prebuilt
ones (`languages.zig.version`) do not.

**Type:** package

**Default:** `config.languages.zig.package when languages.zig is enabled, otherwise pkgs.zig`

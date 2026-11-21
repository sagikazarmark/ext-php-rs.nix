# Real extensions built with ext-php-rs, the ones with the most downloads among Packagist's PIE
# packages (type php-ext) in November 2026, pinned at their latest releases. They are built
# the way this flake builds any extension, which their own build setups (.cargo/config.toml,
# build scripts, C dependencies) must survive:
#
# - natively against PHP 8.4, loaded by the install check;
# - their .phpt tests, through php.withExtensions: upstream's where the release has them,
#   otherwise ours (tests/real-world/<extension>);
# - cross-compiled for x86_64 glibc NTS, aarch64 musl ZTS and aarch64 macOS NTS, checked for
#   their shared libraries, glibc floor and minimum macOS.
#
# Checks are named <extension>-<build>, e.g. mjml-tests.
{
  lib,
  runCommand,
  fetchFromGitHub,
  php84,
  rustPhpPlatform,
}:

let
  extensions = {
    # https://packagist.org/packages/hosmelq/ext-anydoc: document format detection and
    # conversion (Firecrawl's anydoc). ext-php-rs 0.16.5, a build script of its own
    # (ext-php-rs-build), a Cargo package named ext-anydoc with the module anydoc.
    anydoc = {
      args = {
        pname = "ext-anydoc";
        version = "1.0.0";
        src = fetchFromGitHub {
          owner = "hosmelq";
          repo = "ext-anydoc";
          rev = "05fefab7f655f2f32ffa2da9e8a11ae9bd5e4aeb"; # v1.0.0
          hash = "sha256-CvQYN3fceSad2GgdGDpkb48NLPS6aN/4BV5kaNiLaIM=";
        };
        cargoHash = "sha256-ZrEYvG8y5cIiPAX3qipVLw1UQ4d0WdPgkf2JyY75n8w=";
        extensionName = "anydoc";
        libName = "anydoc";
      };
      # GitHub's archive of the release leaves its tests out.
      tests = ./real-world/anydoc;
    };

    # https://packagist.org/packages/bsn4/grpc: a gRPC client compatible with the C extension
    # grpc, on tonic and tokio. ext-php-rs 0.15.15 with closures, ring (C and assembly), linker
    # flags for Linux in its .cargo/config.toml, a Cargo package named grpc-php-rs with the
    # module grpc.
    grpc = {
      args = {
        pname = "grpc-php-rs";
        version = "0.4.0";
        src = fetchFromGitHub {
          owner = "extphprs";
          repo = "grpc-php-rs";
          rev = "56e3f3b4e97b943eca8f05ee60b1011f4af1cea7"; # v0.4.0
          hash = "sha256-E235+NasMLJPPraksLNj92cZyEbDnftmMGLXKsFHwqA=";
        };
        cargoHash = "sha256-Ittyd/HXbyk60MFRnfAsnj3OrLQqQBsYYBv9dIcQb+c=";
        extensionName = "grpc";
      };
      tests = ./real-world/grpc;
    };

    # https://packagist.org/packages/kcs/mjml: MJML email rendering (mrml). ext-php-rs 0.16.2,
    # a .cargo/config.toml that names aarch64-linux-gnu-gcc as the aarch64 glibc linker.
    mjml =
      let
        src = fetchFromGitHub {
          owner = "alekitto";
          repo = "mjml-php";
          rev = "ea6046804f5e2464fb0e84a3b6af48281c5c3c7a"; # v1.2.2
          hash = "sha256-TfvqBQIDNRuFAIzPtYcbFPtldrt8kwPZj3DfGZzlLZk=";
        };
      in
      {
        args = {
          pname = "mjml";
          version = "1.2.2";
          inherit src;
          cargoHash = "sha256-GwiosItY3Lg02gEgSBvhKoW+1g1mxRswCqGZEjNXWvw=";
        };
        # Its own (rendering, files, fonts, titles and errors), but 0001-include, which fetches a
        # template from GitHub.
        tests = runCommand "mjml-tests" { } ''
          cp -r --no-preserve=mode ${src}/tests "$out"
          rm "$out"/{,integration/}0001-include.php*
        '';
      };
  };

  # Each extension's builds: native, against PHP 8.4, and portable, by target and thread safety.
  buildsOf =
    extension:
    let
      inherit (rustPhpPlatform.targets) x86_64-linux-glibc aarch64-linux-musl aarch64-darwin;
      build = args: rustPhpPlatform.buildRustPhpExtension (extension.args // args);
      portable =
        target: zts:
        build {
          php = php84;
          inherit target zts;
        };
    in
    {
      native = build { php = php84; };
      portable = {
        x86_64-linux-glibc-nts = portable x86_64-linux-glibc false;
        aarch64-linux-musl-zts = portable aarch64-linux-musl true;
        aarch64-darwin-nts = portable aarch64-darwin false;
      };
    };

  builds = lib.mapAttrs (_: buildsOf) extensions;
in
{
  checks = lib.concatMapAttrs (
    name: extension:
    let
      inherit (builds.${name}) native portable;
    in
    {
      "${name}-php84" = native;
      "${name}-tests" = rustPhpPlatform.runPhpTests {
        name = "${name}-tests";
        php = php84;
        extensions = [ native ];
        src = extension.tests;
      };
    }
    // lib.mapAttrs' (build: lib.nameValuePair "${name}-${build}") portable
  ) extensions;

  # For loading on Linux and macOS machines (.github/workflows/ci.yaml): the portable builds,
  # and the .phpt tests by module name.
  portableBuilds = lib.concatMap (extension: lib.attrValues extension.portable) (
    lib.attrValues builds
  );

  tests = lib.mapAttrs' (
    name: extension: lib.nameValuePair builds.${name}.native.extensionName extension.tests
  ) extensions;
}

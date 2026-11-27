# The headers of a PHP to build an extension against for a target (targets.nix): `php`'s
# version configured for that target (OS, CPU, C library, thread safety), with a php-config
# that runs on the build platform and a stub for `php -i` (write-php-stub.sh).
#
# An extension needs main/php_config.h from a PHP configured for the platform it will run on:
# what configure detects there changes the layout of the structs ext-php-rs binds (the executor
# globals gain timer fields in a ZTS build on Linux, the core globals differ between Linux and
# macOS). Configure only, no build: it runs PHP's configure with `zig cc` for the target, on any
# build platform, and installs the php-config it writes.
{
  lib,
  stdenv,
  zig,
}:

{
  php,
  target,
  # Thread safety (ZTS) of the configured PHP, as nixpkgs' PHP's ztsSupport.
  ztsSupport,
}:

let
  unwrapped = php.unwrapped or php;
  # The shell of the build platform, which runs the scripts.
  inherit (stdenv) shell;
in
assert lib.assertMsg (lib.isBool ztsSupport) "mkPhpHeaders: ztsSupport must be true or false";
stdenv.mkDerivation {
  pname = "php-headers-${target.name}-${if ztsSupport then "zts" else "nts"}";
  inherit (unwrapped) version src;

  # Always a cross configure, even for the build platform's own CPU, so the result does
  # not depend on where it is built.
  configurePlatforms = [ ];
  configureFlags = [
    "--build=${stdenv.buildPlatform.config}"
    "--host=${target.configureHost}"
    # No extensions: they add nothing to the headers an extension is built against.
    "--disable-all"
    "--disable-cgi"
    "--disable-phpdbg"
    "--without-pcre-jit"
    (lib.enableFeature ztsSupport "zts")
    # A configure check that runs a program, which a cross configure cannot, so it would
    # answer no and leave out ZEND_CHECK_STACK_LIMIT (and the executor globals' call
    # stack fields). The stack grows downwards on every target here.
    "php_cv_have_stack_limit=yes"
  ]
  ++ lib.optionals (target.os == "linux") [
    # What gcc answers, and PHP on Linux is built with gcc. zig cc is clang, which has no
    # global register variables: the answer selects the Zend VM kind, and with it the
    # type of opcode handlers in the headers (PHP 8.5's zend_vm_opcode_handler_t). PHP on
    # macOS is built with clang, which answers no, as zig cc does.
    "php_cv_have_global_register_vars=yes"
  ];

  preConfigure = ''
    export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-local-cache
    export CC="${lib.getExe zig} cc -target ${target.zigTarget}"
    export CPP="$CC -E"
  '';

  dontBuild = true;
  installTargets = [ "install-headers" ];
  postInstall = ''
    # configure writes php-config; install-programs would install phpize and man pages too.
    install -Dm755 scripts/php-config "$out/bin/php-config"
    substituteInPlace "$out/bin/php-config" --replace-fail '#! /bin/sh' '#!${shell}'
    bash ${./write-php-stub.sh} "$out" ${shell}
  '';
  dontFixup = true;

  passthru = {
    inherit target ztsSupport;
  };

  meta.description = "PHP ${unwrapped.version} headers configured for ${target.name} (${
    if ztsSupport then "ZTS" else "NTS"
  })";
}

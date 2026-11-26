"""Compare cargoSetupHook's writable, dereferenced copy with its store input."""

import filecmp
import os
import stat
import sys
from pathlib import Path


def check(source, copy):
    # cargoSetupHook follows source symlinks and adds write permission. Neither
    # is a patch, but file contents, file types and executable bits must match.
    original = source.stat().st_mode
    actual = copy.lstat().st_mode
    if stat.S_IFMT(original) != stat.S_IFMT(actual) or (original ^ actual) & 0o111:
        sys.exit(f"Vendor file type or executable bits differ: {copy}")
    if stat.S_ISDIR(original):
        names = set(os.listdir(source))
        changed = names.symmetric_difference(os.listdir(copy))
        if changed:
            sys.exit(f"Vendor entry added or removed: {copy / min(changed)}")
        for name in names:
            check(source / name, copy / name)
    elif not stat.S_ISREG(original) or not filecmp.cmp(source, copy, shallow=False):
        sys.exit(f"Vendor contents differ: {copy}")


check(Path(sys.argv[1]), Path(sys.argv[2]))

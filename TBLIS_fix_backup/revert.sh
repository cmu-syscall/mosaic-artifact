#!/bin/bash
# Revert the TBLIS-only codegen fix (restores originals + rebuilds).
# USAGE: ./revert.sh /path/to/mosaic-artifact
set -e
ROOT="${1:?Usage: ./revert.sh /path/to/mosaic-artifact}"
BK="$ROOT/TBLIS_fix_ORIGINALS"
[ -d "$BK" ] || { echo "ERROR: no backup dir $BK — was apply.sh run?"; exit 1; }

cp -v "$BK/module.cpp.orig"        "$ROOT/mosaic/src/codegen/module.cpp"
cp -v "$BK/codegen_c.cpp.orig"     "$ROOT/mosaic/src/codegen/codegen_c.cpp"
cp -v "$BK/tblis-wrappers.h.orig"  "$ROOT/tensor_algebra_systems_lib/tblis-wrappers.h"
touch "$ROOT/mosaic/src/codegen/module.cpp" "$ROOT/mosaic/src/codegen/codegen_c.cpp"

cd "$ROOT/mosaic/build"
export CMAKE_POLICY_VERSION_MINIMUM=3.5
make -j"$(nproc)" taco-bench
echo "REVERTED to original (hardcoded) codegen."

#!/bin/bash
# ==========================================================================
# TBLIS-only codegen fix for Mosaic — apply script
#
# Makes Mosaic's kernel code-generator link/emit ONLY what the environment
# (mosaic_env_var.sh) specifies — i.e. TBLIS — instead of hardcoding
# gsl/mkl/cuda into every generated kernel.
#
# USAGE:
#   ./apply.sh /path/to/mosaic-artifact
#     where <mosaic-artifact> is the dir that contains BOTH:
#       - mosaic/                       (the compiler source + build/)
#       - tensor_algebra_systems_lib/   (has tblis-wrappers.h)
#     e.g. in the paper's docker container:  ./apply.sh /mosaic-artifact
#
# It backs up the originals to <mosaic-artifact>/TBLIS_fix_ORIGINALS/ first,
# so you can revert (see revert.sh).
# ==========================================================================
set -e

ROOT="${1:?Usage: ./apply.sh /path/to/mosaic-artifact}"
KIT="$(cd "$(dirname "$0")" && pwd)"

MOD="$ROOT/mosaic/src/codegen/module.cpp"
CG="$ROOT/mosaic/src/codegen/codegen_c.cpp"
WR="$ROOT/tensor_algebra_systems_lib/tblis-wrappers.h"
ENVSH="$ROOT/scripts/mosaic_env_var.sh"
BK="$ROOT/TBLIS_fix_ORIGINALS"

for f in "$MOD" "$CG" "$WR" "$ENVSH"; do
  [ -f "$f" ] || { echo "ERROR: expected file not found: $f"; echo "Is '$ROOT' the mosaic-artifact root?"; exit 1; }
done

echo "[1/5] Backing up originals -> $BK"
mkdir -p "$BK"
cp -v "$MOD"   "$BK/module.cpp.orig"
cp -v "$CG"    "$BK/codegen_c.cpp.orig"
cp -v "$WR"    "$BK/tblis-wrappers.h.orig"
cp -v "$ENVSH" "$BK/mosaic_env_var.sh.orig"

echo "[2/5] Installing fixed files (surgical replace)"
cp -v "$KIT/module.cpp"        "$MOD"
cp -v "$KIT/codegen_c.cpp"     "$CG"
cp -v "$KIT/tblis-wrappers.h"  "$WR"

echo "[3/5] Fixing the TBLIS lib name for TBLIS 2.0 (unversioned libtblis.so)"
echo "      old installs used libtblis.so.0.0.0; TBLIS 2.0 installs libtblis.so"
sed -i 's/libtblis\.so\.0\.0\.0/libtblis.so/g' "$ENVSH"
grep DYNAMIC_LIB_FILES "$ENVSH" | sed 's/^/      now: /'

echo "[4/5] Forcing recompile (IMPORTANT: copy can preserve old mtimes, which"
echo "      makes 'make' skip the changed files — touch bumps them to 'now')"
touch "$MOD" "$CG"

echo "[5/5] Rebuilding taco + taco-bench"
cd "$ROOT/mosaic/build"
export CMAKE_POLICY_VERSION_MINIMUM=3.5
make -j"$(nproc)" taco-bench

echo
echo "DONE. Now, in the SAME shell, source the env and run a TBLIS schedule:"
echo "    source $ROOT/scripts/mosaic_env_var.sh"
echo "    cd $ROOT/mosaic/build"
echo "    ./bin/taco-bench --benchmark_filter=bench_gemv_tblis"
echo
echo "To revert:  $KIT/revert.sh $ROOT"

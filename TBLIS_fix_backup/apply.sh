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
BK="$ROOT/TBLIS_fix_ORIGINALS"

for f in "$MOD" "$CG" "$WR"; do
  [ -f "$f" ] || { echo "ERROR: expected file not found: $f"; echo "Is '$ROOT' the mosaic-artifact root?"; exit 1; }
done

echo "[1/4] Backing up originals -> $BK"
mkdir -p "$BK"
cp -v "$MOD" "$BK/module.cpp.orig"
cp -v "$CG"  "$BK/codegen_c.cpp.orig"
cp -v "$WR"  "$BK/tblis-wrappers.h.orig"

echo "[2/4] Installing fixed files (surgical replace)"
cp -v "$KIT/module.cpp"        "$MOD"
cp -v "$KIT/codegen_c.cpp"     "$CG"
cp -v "$KIT/tblis-wrappers.h"  "$WR"

echo "[3/4] Forcing recompile (IMPORTANT: copy can preserve old mtimes, which"
echo "      makes 'make' skip the changed files — touch bumps them to 'now')"
touch "$MOD" "$CG"

echo "[4/4] Rebuilding taco + taco-bench"
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

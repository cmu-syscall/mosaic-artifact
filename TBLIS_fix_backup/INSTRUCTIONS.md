# TBLIS-only Mosaic fix — patch kit

Makes Mosaic run tensor schedules with **TBLIS alone**, on a machine that does
**not** have gsl / mkl / cuda / openblas installed.

## Why this is needed
Some builds of Mosaic (the `evanmwilliams` fork) **hardcode** gsl/mkl/cuda into
*every* JIT-compiled kernel — both the `#include`s it emits and the libraries it
links. So even a pure-TBLIS schedule fails to compile with:
```
fatal error: gsl/gsl_vector.h: No such file or directory
```
This kit restores the artifact's **env-driven** code generation: it reads what to
include/link from environment variables (set by `scripts/mosaic_env_var.sh`),
which are TBLIS-only. Result: kernels need only TBLIS.

## What's in this kit
| File | Replaces | Change |
|---|---|---|
| `module.cpp`       | `mosaic/src/codegen/module.cpp`                 | link cmd → reads `INCLUDE_PATH`/`LIB_PATH`/`DYNAMIC_LIB_FILES` (was: hardcoded `-lopenblas -lcudart -lmkl_*`) |
| `codegen_c.cpp`    | `mosaic/src/codegen/codegen_c.cpp`              | kernel `#include`s → `getenv("INCLUDE_HEADERS")` (was: hardcoded gsl/mkl/cuda includes) |
| `tblis-wrappers.h` | `tensor_algebra_systems_lib/tblis-wrappers.h`   | comments out one dead fn (`tblis_vector_dot_transfer`) that uses a `tblis_vector` type newer TBLIS lacks |

## Prerequisites
- The Mosaic **mosaic-artifact** layout (a dir containing both `mosaic/` and
  `tensor_algebra_systems_lib/`), already built once (so `mosaic/build/` exists).
- **TBLIS installed** at `tensor_algebra_systems_lib/tblis/{include,lib}`
  (with `libtblis.so.0.0.0`).
- `scripts/mosaic_env_var.sh` present (sets `PATH_TO_MOSAIC_ARTIFACT`,
  `INCLUDE_PATH`, `LIB_PATH`, `DYNAMIC_LIB_FILES=-l:libtblis.so.0.0.0`,
  `INCLUDE_HEADERS`).

## Apply it in a DOCKER CONTAINER (the main use case)
From the host (replace `<container>` with your container id/name; `/mosaic-artifact`
is the artifact root inside the paper's image):
```bash
# 1. copy this whole kit into the container
docker cp TBLIS_fix_backup <container>:/tmp/TBLIS_fix_backup
# 2. apply it (backs up originals, replaces the 3 files, touches, rebuilds)
docker exec <container> bash /tmp/TBLIS_fix_backup/apply.sh /mosaic-artifact
# 3. run a TBLIS schedule + see timings (env must be sourced in the same shell)
docker exec <container> bash -lc '
  source /mosaic-artifact/scripts/mosaic_env_var.sh
  cd /mosaic-artifact/mosaic/build
  ./bin/taco-bench --benchmark_filter=bench_gemv_tblis'
```
Revert it later:
```bash
docker exec <container> bash /tmp/TBLIS_fix_backup/revert.sh /mosaic-artifact
```

## Apply it (turnkey, if you're already inside the container / on the box)
```bash
./apply.sh /path/to/mosaic-artifact       # e.g. /mosaic-artifact in the docker container
```
Then, in the SAME shell:
```bash
source /path/to/mosaic-artifact/scripts/mosaic_env_var.sh
cd /path/to/mosaic-artifact/mosaic/build
./bin/taco-bench --benchmark_filter=bench_gemv_tblis     # or bench_plus3_tblis
```
You should see a benchmark table with **Time / CPU** columns — a TBLIS schedule
running and timed. (Read the `_median` rows; small sizes are noisy at first.)

## Manual steps (if you prefer, instead of apply.sh)
1. Back up the 3 target files (see table above).
2. Copy this kit's 3 files over them.
3. **`touch`** the two `.cpp` files — `cp` can keep old timestamps, which makes
   `make` skip recompiling them (it will silently only relink → the fix won't
   take effect). This is the #1 gotcha.
4. `cd mosaic/build && make -j$(nproc) taco-bench`
5. `source scripts/mosaic_env_var.sh`  (REQUIRED — `codegen_c.cpp` now reads
   `INCLUDE_HEADERS`; if unset it crashes on a NULL env var).
6. `./bin/taco-bench --benchmark_filter=bench_gemv_tblis`

## Revert
```bash
./revert.sh /path/to/mosaic-artifact
```
(Restores the originals saved in `<mosaic-artifact>/TBLIS_fix_ORIGINALS/` and rebuilds.)

## Notes / caveats
- **TBLIS-only:** after this, gsl/mkl/cuda schedules won't build (they weren't
  runnable without those libs anyway). TBLIS ops (gemv, matmul, add, ttm, …) work.
- **The `tblis-wrappers.h` patch is version-dependent.** It's only needed if your
  TBLIS lacks the old `tblis_vector` API (error: `unknown type name 'tblis_vector'`).
  If your TBLIS *has* it, you can skip that one file. Applying it anyway only
  disables a vector-dot helper you likely don't use.
- **These are whole-file replacements** matching the mosaic-artifact / evanmwilliams
  fork codebase. On a very different Mosaic version they might not compile — if so,
  revert and apply the same two ideas by hand (env-var link in `module.cpp`,
  `getenv("INCLUDE_HEADERS")` in `codegen_c.cpp`).
- Verified working: `bench_gemv_tblis` (~21 ms @ dim 250) and `bench_plus3_tblis`
  (~15 ms @ dim 100) on Ubuntu 22.04 with TBLIS only.

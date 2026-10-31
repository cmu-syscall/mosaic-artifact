# Docker and build troubleshooting log

This records changes made during this conversation, their validation, and the
remaining build issue. The full Docker build and Fig. 19 workflow have **not**
been verified end to end.

## Source changes

### Dockerfile

- Split the combined setup command into separate `RUN` statements for repository
  setup, package groups, and Python packages.
- Added `ENV CC=gcc CXX=g++`. The downloaded BLIS configure script detects the
  compiler vendor by searching its version banner. Ubuntu's `/usr/bin/cc`
  banner starts with `cc`, which left BLIS's `CC_VENDOR` empty. Explicit `gcc`
  was recognized successfully.
- Added `ENV CMAKE_POLICY_VERSION_MINIMUM=3.10` and
  `-DCMAKE_POLICY_VERSION_MINIMUM=3.10` to the CMake invocation. Initially these
  were 3.5 to address the compatibility error; they were raised to 3.10 after
  CMake warned that compatibility below 3.10 is deprecated.
- These policy settings do not edit downloaded GoogleTest source files or
  install a different CMake version. They apply a compatibility policy floor.
- Small parent/dependency CMake configuration checks passed with the overrides;
  the 3.10 check produced no deprecation warnings. Full image rebuild untested.

The Ubuntu 26.04 base, disabled `zeehio/libxp` repository, pip's
`--break-system-packages` flag, and trailing `# Install tblis` comment were
already present when this work began. They were not changes made by the agent.

### CMake declarations

Raised existing minimum requirements below 3.5 in these files:

- `mosaic/bench/CMakeLists.txt`: 2.8.12 → 3.5.
- `mosaic/bench/benchmark/cmake/GoogleTest.cmake.in`: 2.8.12 → 3.5.
  This template generates a CMakeLists.txt during configuration and was missed
  in the first scan of literal CMakeLists.txt filenames.
- `mosaic/python_bindings/pybind11/CMakeLists.txt`: 3.4 → 3.5.
- `mosaic/python_bindings/pybind11/tests/CMakeLists.txt`: 3.4 → 3.5.
- The six `CMakeLists.txt` files under
  `mosaic/python_bindings/pybind11/tests/test_cmake_build/` in
  `installed_embed`, `installed_function`, `installed_target`,
  `subdirectory_embed`, `subdirectory_function`, and `subdirectory_target`:
  3.4 → 3.5.

The top-level `mosaic/CMakeLists.txt` already declared 3.5.0 when inspected.
The benchmark library's 3.16.3 requirement was preserved. Documentation and
comments mentioning 3.4 were not changed. A repository scan found no remaining
active declarations below 3.5; dependencies fetched later can still contain
older declarations, which is why the Docker policy override is also needed.

### C++ test initializer

In `mosaic/test/tests-tensor_types.cpp`, changed:

```cpp
map<vector<int>,TypeParam> vals = {{{0}, 1.0}, {{2}, 2.0}};
```

to:

```cpp
map<vector<int>,TypeParam> vals = {{{0}, TypeParam(1)}, {{2}, TypeParam(2)}};
```

This avoids forbidden implicit double-to-integer narrowing for integer test
instantiations. The complete source file passed:

```bash
g++ -std=c++14 -pedantic-errors -fsyntax-only \
  -I mosaic/include -I mosaic/test -I mosaic/src \
  mosaic/test/tests-tensor_types.cpp
```

### Python argument help

In `mosaic-benchmarks/data/data_gen.py`, changed `help="% nnz"` to
`help="%% nnz"`. Argparse interprets percent signs as formatting markers;
doubling the sign displays a literal percent. Parser construction, help
formatting, and parsing `--nnz 0.1` passed a local isolated parser check.

## Repair made only inside the running container

Container inspected: `3908489c8da1` (`flamboyant_lederberg`). The failing TBLIS
build is in `/mosaic-artifact/tensor_algebra_systems_src/tblis`, not
`/mosaic-artifact/mosaic/build`.

Its CMake cache selected `/usr/bin/cc` and `/usr/bin/c++`. BLIS's generated
`_deps/blis-build/config.mk` contained an empty `CC_VENDOR`.

Ran the following inside the container:

```bash
cd /mosaic-artifact/tensor_algebra_systems_src/tblis/_deps/blis-build
CC=gcc CXX=g++ ../blis-src/configure \
  --prefix=/mosaic-artifact/tensor_algebra_systems_src/tblis/_deps/blis-build/usr \
  --disable-shared --enable-static --disable-blas --disable-cblas \
  --enable-threading=pthread generic
make -n
```

Configuration then recorded `CC_VENDOR := gcc` and `CC := gcc`, and the dry
run succeeded. Logs were saved inside the container as
`/tmp/mosaic-blis-configure.log` and `/tmp/mosaic-blis-dry-run.log`.
No full compilation was completed by the agent. This container-only repair
does not persist into a newly built image; the Docker compiler environment
settings address compiler selection for new builds.

## LIB_PATH conflict (build workaround verified)

Mosaic's `scripts/mosaic_env_var.sh` exports `LIB_PATH` containing linker flags:

```text
-L/mosaic-artifact/tensor_algebra_systems_lib/tblis/lib -Wl,-R/mosaic-artifact/tensor_algebra_systems_lib/tblis/lib
```

BLIS uses the same variable name for a filesystem output directory.
Inspection of BLIS's `common.mk` confirmed it preserves a nonempty inherited
`LIB_PATH` and uses it to form library output paths. This explains the error
trying to write an output file named `-L/...` and the malformed shared-library
target containing `-Wl,-R/...`.

Build command, from inside the container:

```bash
cd /mosaic-artifact/tensor_algebra_systems_src/tblis
env -u LIB_PATH CC=gcc CXX=g++ cmake --build .
```

This removes Mosaic's linker flags only from the dependency build environment;
it leaves the interactive shell's variable available for Mosaic benchmarks.
This workaround was executed. BLIS built successfully. The plugin then exposed
a stale compiler configuration, repaired as described below. The complete TBLIS
build subsequently succeeded; installation and the Fig. 19 workflow remain unverified.

## Persistence and remaining scope

- Changes under `mosaic-benchmarks`, `mosaic`, `mosaic/bench/benchmark`, and
  `mosaic/python_bindings/pybind11` span nested Git repositories/submodules.
  A parent repository commit alone does not preserve uncommitted nested edits.
- No commits or pushes were made by the agent.
- Existing changes/removals in `mosaic/apps` were not made by the agent.
- The repository's TBLIS download script still pins an older Autotools-based
  revision. The running container contains a newer CMake-based TBLIS checkout;
  that dependency setup has not been incorporated into the Dockerfile.
- Installing every Fig. 19 dependency and validating
  `make run-fig19 && make draw-fig19` remain unfinished.

## Follow-up container repair and successful TBLIS build

Removed `LIB_PATH` from the build process environment with `env -u LIB_PATH`.
The first retry completed BLIS installation but failed at plugin compilation
because its generated configuration still used `/usr/bin/cc`.

Reconfigured the existing TBLIS CMake build:

```bash
cd /mosaic-artifact/tensor_algebra_systems_src/tblis
env -u LIB_PATH CC=gcc CXX=g++ cmake -S . -B . \
  -DCMAKE_C_COMPILER=/usr/bin/gcc \
  -DCMAKE_CXX_COMPILER=/usr/bin/g++ \
  -DCMAKE_INSTALL_PREFIX=/mosaic-artifact/tensor_algebra_systems_lib/tblis \
  -DBLIS_CONFIG_FAMILY=generic
```

CMake regenerated its compiler cache. The plugin config file was still treated
as up to date, so its generated configure rule was explicitly rerun:

```bash
env -u LIB_PATH make -B -f CMakeFiles/plugin-configure.dir/build.make tblis/plugin/config.mk
env -u LIB_PATH CC=gcc CXX=g++ cmake --build . -j 2
```

Result: **build completed successfully**, including `tblis` and `tblis-static`
at 100%. Logs inside the container: `/tmp/mosaic-plugin-configure.log` and
`/tmp/mosaic-tblis-build.log`. These repairs were made in the running container.
Future dependency builds must also avoid inheriting Mosaic's `LIB_PATH`.
No TBLIS install command or Fig. 19 benchmark run was performed in this step.

## Fig. 19 verification (in progress)

- Installed the built TBLIS via `cmake --install` with prefix
  `/mosaic-artifact/tensor_algebra_systems_lib/tblis`. Its cached absolute header
  paths still install some headers under `/usr/local/include`; the shared library
  is in the requested prefix's `lib` directory.
- Installed `libmkl-dev`, `libgsl-dev`, `libopenblas-dev`, and
  `python3-matplotlib` inside the container; added these packages to Dockerfile.
- Updated `scripts/bench-scripts/sddmm/bench.sh` to select headers and libraries
  separately for MKL, GSL, OpenBLAS, TBLIS, and the unaccelerated TACO baseline.
  Added fail-fast shell settings, result-directory creation, automatic artifact
  root discovery, anchored benchmark filters, and `-ltblis` instead of a fixed
  versioned library filename. The newer TBLIS headers also require
  `-D_GNU_SOURCE` for their pthread types under C99.
- Updated the benchmark Makefile to infer/export the artifact root when unset.
  `draw-fig19` selects the headless Agg backend and creates `figs/` if needed.
- Preserved existing container results in `/tmp/fig19-results-before-verification`.
- Started `make run-fig19 && make draw-fig19` inside the container with output
  in `/tmp/fig19-verification.log`. The initial run predates the TBLIS feature
  macro correction and will require a corrected run before final validation.

Verification stopped at the user's request. MKL, GSL, and dot_blas completed;
TACO was in progress. MKL/GSL JSON checks passed for all ten sizes. The final
runner and Makefile were copied into the container, including the TBLIS feature
macro fix. The complete seven-system workflow and final PDF remain unverified.

## Fig. 19 completed successfully

A subsequent read-only check of the user's completed container run found all
seven result files (mkl, gsl, dot_blas, taco, blas, tblis, gemv_blas) contain
median results for all ten expected dimensions, 100 through 1900 in steps of
200, with no reported benchmark errors. Both `sddmm/result/fig19.pdf` and
`figs/fig19.pdf` were regenerated after the final benchmark completed, and each
is 16,640 bytes. This verifies the workflow in the repaired running container;
a fresh Docker image build remains unverified.

## Docker startup automation

Reworked Dockerfile to reproduce the dependency setup in a fresh image:

- Uses Ubuntu 26.04 distribution compiler/CMake packages without extra PPAs or
  i386 architecture setup. Uses distribution Python scientific/plotting packages
  rather than pip overwriting system packages.
- Pins TBLIS to `eb719e718976572e0ab53975f4e0c799faeb35f2`, the revision from
  the working container, and initializes its recursive submodules.
- Configures TBLIS in a separate fresh build directory with explicit gcc/g++,
  generic BLIS, pthread BLIS threading, and the final library install prefix.
  Every dependency configure/build/install runs with `LIB_PATH` removed.
- Builds only Mosaic's `taco-bench` target, with benchmark-library self-tests
  disabled and Git submodule auto-updates disabled. Source submodules must be
  initialized before `docker build`.
- Sets an empty `INCLUDE_HEADERS` for safe executable initialization; the Fig. 19
  runner supplies the actual headers per implementation.
- Defaults to `CMD ["make", "run-fig19"]` from the benchmark Makefile directory.
  Passing `bash` or another command to `docker run` overrides the default.
- Adds `.dockerignore` to exclude host build caches, fetched dependency sources,
  preinstalled TBLIS libraries, and old Fig. 19 results from the image context.
- Documents build/run, optional PDF generation, and PDF copying in `docker.md`.

Fresh-image validation uses tag `mosaic-artifact-fig19`; the previously working
`mosaic-artifact` image and container are not replaced.

### Fresh Docker image validation passed

- `docker build -t mosaic-artifact-fig19 .` completed successfully from the new
  Dockerfile (image ID `822502a033da`).
- Image inspection confirmed default command `["make","run-fig19"]` and workdir
  `/mosaic-artifact/scripts/bench-scripts`.
- Started a separate container, `mosaic-fig19-smoke`, using the runner with only
  its benchmark filter narrowed to dimension 100. All seven implementations
  completed with positive median timings and no reported benchmark errors.
- `make draw-fig19` succeeded in that fresh container and generated a valid
  13,581-byte PDF from the smoke data. The full-size PDF in the host repository
  was not overwritten.
- Full Docker build log: `/tmp/mosaic-fig19-docker-build.log` on the host.
  Smoke log: `/tmp/mosaic-fig19-docker-smoke.log`; copied smoke results:
  `/tmp/mosaic-fig19-fresh-image-results`.
- The full ten-size benchmark was not repeated in the fresh image. The earlier
  complete run passed in the repaired container; the fresh-image smoke checks
  verify that the new Dockerfile supplies all seven implementations and plotting.

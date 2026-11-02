# Multi-schedule benchmarks

Each kernel has separate C++ files in mosaic/bench/multi-bench:
bench_gemm.cpp, bench_spmm.cpp, and bench_sddmm.cpp for synthetic inputs;
bench_suitesparse_gemm.cpp, bench_suitesparse_spmm.cpp, and
bench_suitesparse_sddmm.cpp for Matrix Market inputs. Each defines its expression,
registers library interfaces, calls autoAccelerate once, and uses Google Benchmark
DenseRange to benchmark the resulting schedules separately. Matrix Market input
is read once with TACO's readMTX. Synthetic inputs use taco::util::fillTensor
with FillMethod::Random, then the existing castToTypeZero<float> benchmark helper.
multi_bench.h shares configuration, interface selection, source saving, and the
Google Benchmark callback. Each kernel file still constructs its own operands,
defines its expression, and calls autoAccelerate. There is no common.cpp or
Python execution runner.
Each executable parses its input flags before passing the remaining flags to
Google Benchmark. The CMake targets are needed because these files have
their own main functions and register schedules after loading the chosen input.

## Build

From the artifact root, after initializing submodules:

```sh
cmake -S mosaic -B mosaic/build -DCMAKE_BUILD_TYPE=Release
cmake --build mosaic/build --target taco-multi-gemm taco-multi-spmm taco-multi-sddmm --parallel 4
cmake --build mosaic/build --target taco-multi-suitesparse-gemm taco-multi-suitesparse-spmm taco-multi-suitesparse-sddmm --parallel 4
```

Older project CMake files may need -DCMAKE_POLICY_VERSION_MINIMUM=3.5 with
CMake 4. Existing taco-bench and figure targets are unchanged.

## Run

Configure and source scripts/mosaic_env_var.sh for the libraries you select.
INTERFACES controls which interfaces are offered to autoAccelerate; it does not
install libraries or configure headers/link flags. The shell runner inherits
INCLUDE_HEADERS, INCLUDE_PATH, LIB_PATH, DYNAMIC_LIB_FILES and TACO_CFLAGS.
Set library thread-count variables explicitly for comparable runs.

From scripts/bench-scripts:

```sh
make list-multi-interfaces
make run-multi-gemm DIMS=250,500 INTERFACES='tblis.tblis_tensor_mult'
make run-multi-spmm DIMS=250 DENSITIES=0.01,0.1 INTERFACES='mkl.mkl_sparse_s_mm_internal'
make run-multi-sddmm DIMS=250 DENSITIES=0.1 INTERFACES=taco
make run-multi-gemm DIMS=250 CONSTANT_FOLDING=false INTERFACES=taco
make run-multi-spmm INPUT=matrix-market MATRIX=/absolute/path/matrix.mtx INTERFACES='mkl.*'
```

- INPUT: synthetic (default) or matrix-market.
- DIMS: comma-separated square sizes, default 250.
- DENSITIES: comma-separated target nonzero fractions in [0,1], default 1.
  A density of 0.1 means approximately 90% zeros.
- MATRIX: required for matrix-market input. Omit DIMS/DENSITIES in this mode.
- INTERFACES: comma-separated library.function selectors, default taco.
  For example, 'tblis.tblis_tensor_mult,mkl.cblas_sgemm' or 'mkl.*'.
  Whitespace around comma-separated entries is accepted. Quote wildcards in shells.
  BACKENDS remains a legacy alias when INTERFACES is omitted. Bare library names
  now mean library.* rather than one kernel-specific interface.
- REPETITIONS: default 10; one timed execution per repetition.
- CONSTANT_FOLDING: true (default) or false. Passed as --constant-folding to
  autoAccelerate's optional third argument. False disables simplification, not
  structural deduplication. Bound schedules are never simplified.
- WARMUP: Google Benchmark's minimum warmup duration in seconds, default 0.
  For example WARMUP=0.1. Warmup calls are not reported as repetitions.
- FILTER: Google Benchmark regex, default all schedules.
- OUT: a new result directory; defaults under artifact/local-tests.
- MULTI_BENCH_BIN: optional executable override for testing another build.

The shell script only loops over input configurations and redirects output.
INPUT=matrix-market selects the taco-multi-suitesparse-<kernel> executable.
The runner passes --matrix or --dim/--density, plus --interfaces and --constant-folding;
MULTI_* input environment variables are no longer read by the executables.
Google Benchmark handles schedule iteration, repetitions, and JSON reporting.
For synthetic data, configurations are the Cartesian product of DIMS and
DENSITIES. For real input, the matrix determines the dimension. Only square,
real general/symmetric Matrix Market coordinate/array inputs are supported.

GEMM uses dense A/B, SpMM uses CSR A/dense B, and SDDMM uses a CSR mask with
dense A/B and dense output. Density or the input file supplies A for GEMM/SpMM
and the mask for SDDMM. Remaining operands use TACO's random filler. The filler
selects positions without replacement; fractional entry counts are rounded up
by its loop bound. It generates double values approximately in [-1e7,1e7],
which are converted to float without replacing zeros. Actual nonzero density
is recorded in JSON. Inputs are created once and shared by all schedules in
that process. Separate runs are not seed-reproducible; --seed/SEED is no longer
an input option. TACO's Random matrix filler is used only with square matrices
here because its coordinate mapping is not general for rectangular inputs.

For example, from a fresh output directory containing a code/ subdirectory:

```sh
/path/to/taco-multi-gemm --dim=250 --density=0.1 --interfaces=tblis.tblis_tensor_mult --benchmark_repetitions=10 --benchmark_out=results.json --benchmark_out_format=json
```

For file input, use taco-multi-suitesparse-gemm with
--matrix=/absolute/path/matrix.mtx instead of --dim/--density.
The Make interface above remains unchanged. --dim and --density are synthetic-only
flags; --matrix is a SuiteSparse-only flag.

## Interface catalog

Every executable accepts -h, --h, or --help for options and the dictionary of
registered functions, grouped by library. --list-interfaces prints only the
dictionary and its scope notes. Neither command loads input or runs benchmarks,
including for SuiteSparse executables. --benchmark_help shows Google Benchmark's
own flags. The catalog is the same in all six executables; Mosaic decides which
supplied interfaces match a kernel or its subexpressions.

Function names come from each existing interface's getFunctionName(), so some
are Mosaic wrapper symbols rather than direct library symbols. For example,
tblis.tblis_tensor_mult selects all existing GEMM/GEMV/TTM/TTV variants with that
function name. mkl.* selects all registered MKL entries, including its CBLAS
variants. Overlapping selectors do not register an interface object twice.
Unknown libraries/functions and empty selectors are errors.

The CPU library groups are tblis, gsl, mkl, blas, openblas, accelerate, and avx2.
blas, openblas, and accelerate are provider names for existing CBLAS interfaces; the link environment
still determines which implementation runs. Selecting CBLAS functions through
multiple providers is rejected because their symbols cannot distinguish them.
Selecting a non-CBLAS MKL wrapper together with another CBLAS provider is allowed.
Accelerate requires native macOS; MKL requires a compatible x86 build.

The catalog is not an installation check or a guarantee that every candidate
produces valid code. Symmetric-only interfaces are excluded because these inputs
are not guaranteed symmetric and their interfaces do not enforce the condition.
MklAdd is excluded because its existing sparse-add wrapper passes an uninitialized
output pointer. TblisDot and the legacy MKL GEMV adapters are excluded because
their required wrapper functions are absent. The legacy one-dimension MKL GEMM
adapter is excluded; use mkl.cblas_sgemm instead. The CBLAS GEMM/GEMV declarations
now use the correct row-major leading dimensions, including rectangular slices.
MKL SpMM now passes the output values pointer and its wrapper reads the input
dimensions instead of assuming every matrix is square.

GSL uses the existing GSLMM interface. Configure generated C with
gsl/gsl_blas.h and gsl-wrappers.h, the appropriate include paths, and GSL's
link flags (typically -lgsl -lgslcblas -lm). gsl-wrappers.h no longer requires
TBLIS or the GSL tensor extension. GSL and MKL's CBLAS headers can conflict;
do not include both sets blindly in INCLUDE_HEADERS.

## CUDA and AVX

The existing cuda_interface.h now defines CudaGemm, CudaGemv, and CudaSpmm,
alongside CudaSpmv. All use the standard AbstractFunctionInterface API and
the same autoAccelerate/compile/packed-call workflow as CPU interfaces.
The existing artifact cuda-wrappers.h implements their host-pointer adapters
using cuBLAS GEMM/GEMV and cuSPARSE's generic CSR SpMM/SpMV APIs.
There is no CUDA-specific benchmark executable or alternative execution path.

Selectors:
- cublas.mosaic_cuda_sgemm, cublas.mosaic_cuda_sgemv, or cublas.*
- cusparse.mosaic_cuda_spmm, cusparse.cuda_spmv, or cusparse.*
- cuda.*: both groups, without duplicate registrations
- avx2._mm256_storeu_ps: the existing eight-element AVXSaxpy interface

CUDA wrappers require a CUDA 12 toolkit and an NVIDIA GPU. On a GPU compute node,
configure the same environment variables used by the other artifact benchmarks,
with CUDA_HOME pointing at the installed toolkit:

```sh
export PATH_TO_MOSAIC_ARTIFACT=/path/to/mosaic-artifact
export INCLUDE_HEADERS='#include "cuda-wrappers.h"'
export INCLUDE_PATH="-I$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib -I$CUDA_HOME/include"
export LIB_PATH="-L$CUDA_HOME/lib64 -Wl,-rpath,$CUDA_HOME/lib64"
export DYNAMIC_LIB_FILES='-lcublas -lcusparse -lcudart'
cd "$PATH_TO_MOSAIC_ARTIFACT/scripts/bench-scripts"
make run-multi-gemm DIMS=250 INTERFACES='cublas.mosaic_cuda_sgemm'
make run-multi-spmm DIMS=250 DENSITIES=0.1 INTERFACES='cusparse.mosaic_cuda_spmm'
```

Adjust toolkit paths to the installed module layout. No nvcc compilation of the
benchmark or TACO-generated C is required: these adapters call CUDA's host C APIs.
When mixing CPU libraries, include/link their dependencies too; selection alone
does not install or configure any library. A Mac's Docker VM cannot run CUDA.

Timing includes allocations, handle creation, host/device transfers, synchronized
library execution, and cleanup. cuBLAS uses pedantic math rather than TF32.
This is an end-to-end host-call comparison, not device-resident kernel timing.
No global GPU caches or persistent handles are introduced.

Sparse interfaces require CSR; dense cuBLAS interfaces require dense storage.
Mosaic must produce a valid mapping/conversion; the benchmark does not force one.
There is no direct cuSPARSE SDDMM binding: this benchmark's weighted-mask,
dense-output expression differs from cuSPARSE's sparse sampled-output contract.
SDDMM can still offer GEMM/GEMV candidates to Mosaic for subexpression matching.
We do not emulate a missing binding in a wrapper.

AVX2 requires an x86 CPU that supports AVX2 and generated-C flags/header inclusion,
typically INCLUDE_HEADERS='#include <immintrin.h>' and TACO_CFLAGS containing
-mavx2 alongside the normal optimization/shared-library flags. Its fixed-width
addition interface need not match a GEMM/SpMM/SDDMM expression.

The paper's Stardust backend targets the Capstan simulator and uses the original
make stardust-csv workflow, not a callable CPU/GPU library. Its placeholder
nanosleep/escape interfaces are not registered as timed implementations here.
The GSL tensor extension implements tensor addition, not these products, and the
TensorFlow demo only queries a version; neither is added to these benchmarks.

## Output

Each numbered configuration directory contains:
- results.json: Google Benchmark timings and bound-schedule labels, with resolved
  function selections, input generator, and timing scope in context via Google
  Benchmark's AddCustomContext.
- code/schedule0.c, code/schedule1.c, etc.: generated C for each selected schedule,
  saved outside timing, once across repetitions. Failed compilations also save
  their source when it is available. No file is created if no C was generated.

No schedule/source printouts or console timing report are produced. The runner
does not display upstream console output; no output.txt, config.txt, or status.txt is
created. Per-schedule failures are recorded in results.json. Failed processes
also retain errors.log with stdout and stderr, including compiler diagnostics and failures before JSON
creation. Successful runs remove this diagnostic file.

The runner refuses to overwrite an existing output directory. Compilation/file
errors and empty benchmark selections cause a nonzero exit status.
Setup failures may occur before results.json exists. Only the packed function
call is timed. Setup, source-file output, compilation, and assembly are outside
the timed loop. There is no reference calculation, result comparison, or
packed-function return-code check. A recorded timing does not establish
numerical correctness. Dense input storage costs O(n^2).

Schedule indices are local to a configuration, not identities across dimensions.
Source revision/hash manifests from the
previous Python runner are no longer generated.

## Plot

Install matplotlib in the Python environment used for plotting. From
scripts/bench-scripts, pass the same OUT directory used for the run:

```sh
make draw-multi-gemm OUT=/mosaic-artifact/local-tests/my-gemm-run
make draw-multi-spmm OUT=/mosaic-artifact/local-tests/my-spmm-run
make draw-multi-sddmm OUT=/mosaic-artifact/local-tests/my-sddmm-run
```

OUT can also identify a single numbered configuration directory. Each
configuration gets plots/schedules.pdf, plots/schedules.html, and
plots/manifest.json. Repeating draw replaces these plot files, not raw results.
PYTHON=/path/to/python selects a Python environment with matplotlib installed.

Bars show median real_time in milliseconds on a linear axis starting at zero, with actual
bound schedules as x-axis labels. The HTML chart scrolls horizontally. Medians
are calculated from individual repetitions when present, otherwise from the
reported median aggregate. Labels can come from either kind of result.
Configurations are never merged by schedule index. Failed schedules are excluded
from bars and listed in the HTML. Check the run command's exit status as well:
an interrupted run may leave incomplete or missing JSON.
This plotter is separate from the original figure scripts and does not change them.

## Known limitations

Backend selection does not guarantee a binding. Matching now rejects
inconsistent tensor/index mappings, collapsed distinct interface indices, and
incompatible reduction variables. These are compiler checks, not benchmark
filters. Rewrite depth is unchanged. autoAccelerate optionally simplifies constants in unbound schedules after
matching, then removes structural duplicates conservatively. Schedules containing
library bindings are left unchanged. Literal addition, subtraction, multiplication,
and negation use TACO's existing typed arithmetic without added overflow checks.
Division is left unchanged except for division by one. Floating-point addition
and subtraction of zero, and multiplication by zero, use relaxed algebraic
semantics rather than strict IEEE behavior for signed zero, NaN, and infinity.
Multiplication by zero does not discard opaque function calls. Bound nodes are treated as
opaque during deduplication, so distinct bindings are not accidentally merged.

## Timing and reuse

TACO_BENCH expands to static BENCHMARK registration. These benchmarks enumerate
schedules after reading input flags, so they use Google Benchmark's standard
RegisterBenchmark and DenseRange instead. They retain one packed compute call per
measured iteration, real-time milliseconds, and ten repetitions from the Make
runner. Direct executable invocations must supply --benchmark_repetitions=10
to request ten repetitions. The six targets have separate main functions and
must not be linked into taco-bench or benchmark_main.

In the vendored Google Benchmark revision, BenchmarkRunner uses a registered
MinWarmUpTime only when the benchmark also has a nonzero MinTime. TACO_BENCH
does not set MinTime, so its MinWarmUpTime(10) is not effective by itself.
WARMUP forwards the standard --benchmark_min_warmup_time flag instead. Default
zero preserves the existing measured workflow; request warmup explicitly for
steady-state comparisons. Input loading, scheduling, compilation, assembly, and
source saving are outside the timed loop. Warmup may run multiple packed calls;
the measured repetition still runs one.

The native helpers reused here are fillTensor, castToTypeZero, readMTX,
IndexNotationRewriter, typed literal arithmetic, replace for result-tensor
identity, compile/assemble/compute_split, and Google Benchmark JSON reporting.
The null-interface assertion remains because it guards a pointer dereference.
Duplicate-expression lookup uses std::any_of, compatible with this project's
C++14 build; std::ranges::filter_view requires C++20.

## Reproducing the environment

Docker is optional: native builds use the same CMake targets. Linux/amd64 Docker
on an Apple Silicon Mac is useful for MKL compatibility, but its timings include
CPU emulation and should not be presented as native hardware performance.
CUDA runs require an NVIDIA compute node, not the Mac container or a login node.

For the TACO-only smoke test, clear external-library injection explicitly:

```sh
export INCLUDE_HEADERS='' INCLUDE_PATH='' LIB_PATH='' DYNAMIC_LIB_FILES=''
cd /mosaic-artifact/scripts/bench-scripts
make run-multi-gemm DIMS=8 REPETITIONS=2 OUT=/mosaic-artifact/local-tests/smoke-gemm
make draw-multi-gemm OUT=/mosaic-artifact/local-tests/smoke-gemm
```

Use a new OUT for each invocation. The runner does not modify your source/link
environment. A working baseline does not prove external libraries are installed.

On Ubuntu 22.04, OpenBLAS and GSL development packages are libopenblas-dev and
libgsl-dev. MKL is optional and x86-specific; the existing container uses
libmkl-dev with the LP64 sequential interface. Configure only the chosen provider
of cblas symbols. For example, TBLIS plus MKL in the existing container:

```sh
export R=/mosaic-artifact
export INCLUDE_HEADERS='#include <mkl.h>
#include "tblis.h"
#include "tblis-wrappers.h"
#include "mkl-wrappers.h"'
export INCLUDE_PATH="-I/usr/include/mkl -I$R/tensor_algebra_systems_lib -I$R/tensor_algebra_systems_lib/tblis/include -I$R/tensor_algebra_systems_lib/tblis/include/tblis"
export LIB_PATH="-L$R/tensor_algebra_systems_lib/tblis/lib -Wl,-rpath,$R/tensor_algebra_systems_lib/tblis/lib"
export DYNAMIC_LIB_FILES='-ltblis -lmkl_rt -lpthread -lm -ldl'
export MKL_THREADING_LAYER=SEQUENTIAL MKL_INTERFACE_LAYER=LP64
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 TBLIS_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
make run-multi-gemm DIMS=250,500 DENSITIES=0.1,1 INTERFACES='tblis.*,mkl.*'
```

Use MKL's runtime dispatcher rather than linking a CPU-specific libmkl_avx2
implementation. In this container, linking only the individual MKL layers into
a locally loaded generated .so caused a dispatch-library symbol error; the
runtime-dispatch configuration above avoids that error without changing Mosaic's
loader or hardcoding a CPU instruction set.

The installed TBLIS source in the existing container is v1.3.0, commit
c4f81e08b2827e72335baa7bf91a245f72c43970. Do not silently replace it with the
latest API. For a separate clean prefix, clone the upstream repository, check
out that commit, initialize its submodules, then configure/build/install:

```sh
git clone https://github.com/MatthewsResearchGroup/tblis.git tblis-src
cd tblis-src
git checkout --detach c4f81e08b2827e72335baa7bf91a245f72c43970
git submodule update --init --recursive
./configure --prefix=/mosaic-artifact/tensor_algebra_systems_lib/tblis
make -j4
make install
```

This pins the existing runtime rather than claiming compatibility with every
TBLIS version. Preserve the compiler/toolkit and thread settings when comparing
results. The artifact's older tblis_download.sh pins a different commit.

For Delta, build these same executables for its CPU architecture. Obtain a Slurm
GPU allocation using your site's account/partition settings before running the
CUDA commands above. Set a short job time limit, start with DIMS=8 and
REPETITIONS=2, and check for both a library-bound JSON label and a successful
run before increasing sizes. GPU execution is left to the user; CPU/header
checks are not evidence of GPU correctness or performance.

The permanent compiler regressions can be run without external libraries:

```sh
cmake --build mosaic/build --target taco-test --parallel 4
INCLUDE_HEADERS='' INCLUDE_PATH='' LIB_PATH='' DYNAMIC_LIB_FILES='' \
  mosaic/build/bin/taco-test --gtest_filter='scheduleConstants.*:acceleratorMatches.*'
```

## Verification (October 30, 2026)

All six executables built natively on macOS and in an isolated Ubuntu 22.04
linux/amd64 source build inside the existing Docker container.

- 42 focused compiler tests passed, including 2D/3D simplification, compiled
  rank-three reduction, optional folding, matching, and temporary dimensions.
- 26 native configurations passed: TACO and Accelerate, synthetic dimensions
  8/32/64 as applicable, zero/partial/full density, all three Matrix Market
  executables on the small ds33.mtx fixture, and folding disabled with warmup.
- 45 Docker configurations passed: 27 combined TBLIS/MKL cases across all three
  kernels, dimensions 8/64/250 and densities 0/0.1/1; 12 GSL cases at 8/64 and
  densities 0.1/1; and six OpenBLAS cases at 8 and densities 0.1/1.
- These runs produced 650 individual timing rows without reported errors.
  Each Docker schedule had its generated C file. PDF/HTML plotting succeeded.
- A separate temporary numerical check validated 14 TBLIS/MKL and 10 GSL
  rectangular schedules, twice each, against scalar reference calculations.
  It was removed after verification; numerical checks are not in the benchmarks.
- An invalid-dimension run retained errors.log and returned failure as expected.

These are bounded checks, not a complete compiler or performance evaluation.
CUDA execution on Delta remains unverified and is left to the user. AVX2 was
not runtime-tested. The updated Dockerfile was not rebuilt as a fresh image;
the Docker checks used installed dependencies and a separate source/build tree,
without replacing /mosaic-artifact in the existing container.

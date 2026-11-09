# Multi-schedule benchmarks

For a clean dependency installation and reproducible container build, see
[the Docker workflow](../../../docker.md). It builds these targets from source,
installs the supported CPU libraries, and configures them through
`source scripts/mosaic_env_var.sh tblis,mkl` (or another documented selection).
`bash scripts/docker-smoke.sh /results/new-smoke-directory` checks the normal
Make workflow in a newly built container.

Each kernel has separate C++ files in mosaic/bench/multi-bench:
bench_gemm.cpp, bench_spmm.cpp, and bench_sddmm.cpp for synthetic inputs;
bench_suitesparse_gemm.cpp, bench_suitesparse_spmm.cpp, and
bench_suitesparse_sddmm.cpp for Matrix Market inputs. Each defines its expression,
registers library interfaces, calls autoAccelerate once, and uses Google Benchmark
DenseRange to benchmark the resulting schedules separately. Matrix Market input
is read once with TACO's readMTX. Synthetic inputs use taco::util::fillTensor
with FillMethod::Random, then the existing castToTypeZero<float> benchmark helper.
multi_bench.h shares configuration, interface selection, source saving, and the
Google Benchmark callback. Synthetic-only bench_ttv.cpp, bench_blockspmm.cpp,
and bench_spadd.cpp add the other pictured kernels. Each kernel file constructs its own operands,
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
cmake --build mosaic/build --target taco-multi-ttv taco-multi-blockspmm taco-multi-spadd --parallel 4
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
- For ttv/blockspmm, DIMS is the extent of every tensor mode and defaults to 10.
  Command-line DIMS overrides this default. These kernels allocate O(n^3) and
  O(n^4) input storage, respectively; do not reuse large GEMM sizes blindly.
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

SDDMM writes the reduction explicitly as
`mask(i,j) * sum(k, A(i,k) * B(k,j))`. This exposes the dense contraction to
the usual subexpression matcher without claiming that the CSR mask is dense.
This representation requires lowering and runtime argument packing to use the
same concrete-assignment argument order. Use the pinned Mosaic submodule, not an
older binary. The benchmark does not force a library binding or substitute a
manually accelerated statement when no candidate matches.

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
own flags. The catalog is the same in all nine executables; Mosaic decides which
supplied interfaces match a kernel or its subexpressions.

Function names come from each existing interface's getFunctionName(), so some
are Mosaic wrapper symbols rather than direct library symbols. For example,
tblis.tblis_tensor_mult selects all existing GEMM/GEMV/TTM/TTV variants with that
function name. mkl.* selects all registered MKL entries, including its CBLAS
variants. Overlapping selectors do not register an interface object twice.
Unknown libraries/functions and empty selectors are errors.

The CPU library groups are tblis, gsl, mkl, blas, openblas, and accelerate.
blas, openblas, and accelerate are provider names for existing CBLAS interfaces; the link environment
still determines which implementation runs. Selecting CBLAS functions through
multiple providers is rejected because their symbols cannot distinguish them.
MKL dense wrappers that call CBLAS also count as selecting the MKL provider.
Selecting a sparse MKL wrapper together with another CBLAS provider is allowed.
Accelerate requires native macOS; MKL requires a compatible x86 build.

The catalog is not an installation check or a guarantee that every candidate
produces valid code. Symmetric-only interfaces are excluded because these inputs
are not guaranteed symmetric and their interfaces do not enforce the condition.
MklAdd is excluded because its existing sparse-add wrapper passes an uninitialized
output pointer. TBLIS dot and MKL dense GEMM/GEMV and CSR GEMV wrappers are
registered as tblis.tblis_vector_dot_transfer, mkl.sgemm_mkl_internal,
mkl.sgemv_mkl_internal, and mkl.mkl_scsrgemv_internal. Copy the matching
tensor_algebra_systems_lib headers when updating the Mosaic interface headers.
The MKL dense adapters accept both matrix dimensions. The CBLAS GEMM/GEMV declarations
now use the correct row-major leading dimensions, including rectangular slices.
MKL SpMM now passes the output values pointer and its wrapper reads the input
dimensions instead of assuming every matrix is square.

TBLIS overwrite products (GEMM/GEMV/TTM/TTV) set the output descriptor's scalar
to zero; otherwise the library adds the previous output values. In-place addition
interfaces retain scalar one. TBLIS tensor descriptors and GSL vector/matrix
descriptors are released through each interface's callAfter hook.

The CPU interface audit checks rectangular GEMM/GEMV/SpMM, dot products,
rank-three TTM/TTV, and accumulation against independent scalar references,
including two calls to the same compiled function. This does not establish GPU
correctness or validate excluded legacy interfaces.

GSL uses the existing GSLMM interface. Configure generated C with
gsl/gsl_blas.h and gsl-wrappers.h, the appropriate include paths, and GSL's
link flags (typically -lgsl -lgslcblas -lm). gsl-wrappers.h no longer requires
TBLIS or the GSL tensor extension. GSL and MKL's CBLAS headers can conflict;
do not include both sets blindly in INCLUDE_HEADERS.

## Functions shown in the paper

The existing GEMM, SpMM, and SDDMM Make targets share this catalog. A selector
offers an interface to autoAccelerate; it does not force a match, change a sparse
operand to dense storage, or change the benchmark's mathematical expression.

| Paper legend | INTERFACES selector | Scope |
| --- | --- | --- |
| Intel MKL GEMM | `mkl.cblas_sgemm`, `mkl.sgemm_mkl_internal` | Row-major adapters supporting rectangular products |
| Intel MKL GEMV | `mkl.cblas_sgemv` | MKL's CBLAS implementation |
| Intel MKL Dot | `mkl.cblas_sdot` or `mkl.sdot_mkl_internal` | Direct CBLAS or the existing MKL dot wrapper |
| BLAS/CBLAS GEMM | `openblas.cblas_sgemm` | OpenBLAS in the Linux container |
| BLAS/CBLAS GEMV | `openblas.cblas_sgemv` | OpenBLAS in the Linux container |
| CBLAS Dot | `openblas.cblas_sdot` | OpenBLAS in the Linux container |
| GSL GEMM | `gsl.gsl_blas_sgemm` | Existing GSL matrix interface |
| GSL GEMV | `gsl.gsl_blas_sgemv` | Existing GSL vector interfaces |
| TBLIS GEMM / TTV | `tblis.tblis_tensor_mult` | Selects GEMM, GEMV, TTM, and TTV interface variants |
| TACO | `taco` | Unbound baseline; also included with external selections |
| Intel MKL SpMMAdd | Not enabled | Existing sparse-add wrapper has an uninitialized output handle and does not populate the result tensor |
| Stardust SpMMAdd | Separate `make stardust-csv` workflow | Simulator backend, not a native CPU library |

SpMMAdd in this figure is sparse matrix addition, not our SpMM multiplication
target. Use the new synthetic-only targets below for these different expressions.
The original figure runners remain unchanged.

| Run target / draw target suffix | Expression | Input / output storage |
| --- | --- | --- |
| `ttv` | `res(i,j) = A(i,j,k) * B(k)` | Dense rank-three A, dense vector B, dense matrix result |
| `blockspmm` | `res(i,k,m,p) = A(i,k,j,l) * B(j,l,m,p)` | A: Sparse/Dense/Sparse/Dense; B/result: dense rank-four |
| `spadd` | `res(i,j) = A(i,j) + B(i,j)` | CSR inputs and CSR result |

TTV uses TACO's rank-three random filler and vector filler. BlockSpMM uses the
original blocked benchmark's expression and storage layout. TACO's random matrix
filler selects a CSR mask of n-by-n blocks; each selected n-by-n block is filled
with 100, and B is filled densely with 100. TACO's filler does not support rank
four, so block expansion uses explicit loops. DENSITIES controls the fraction of
selected blocks, not independent entries. Sparse addition fills both inputs at
the requested density; JSON reports the actual density of A, not their union.

Each file calls autoAccelerate once and shares the same Google Benchmark timing,
source saving, and JSON reporting. Result allocation uses the owner's shape and
format, so rank-four results and CSR addition do not become dense matrices.
Plot titles show the input tensor's mode extents. Matrix Market input is rejected
for these new targets rather than interpreting a matrix as a higher-rank tensor.

```sh
make run-multi-ttv DIMS=3,10 DENSITIES=1 INTERFACES='tblis.*,mkl.*' OUT="$R/local-tests/ttv"
make draw-multi-ttv OUT="$R/local-tests/ttv"
make run-multi-blockspmm DIMS=3,5 DENSITIES=0.05 INTERFACES='tblis.*,mkl.*' OUT="$R/local-tests/blockspmm"
make draw-multi-blockspmm OUT="$R/local-tests/blockspmm"
make run-multi-spadd DIMS=8,64 DENSITIES=0.1,1 INTERFACES=taco OUT="$R/local-tests/spadd"
make draw-multi-spadd OUT="$R/local-tests/spadd"
```

Configure libraries before running these commands, as below. Sparse addition
currently has only TACO candidates: MKL's unsafe sparse-add adapter is still
excluded. No nanosleep-based Stardust placeholder is timed. Higher-rank inputs
do not guarantee library bindings: the paper's explicit holdConstant mappings
are not silently substituted for autoAccelerate's returned schedules.

Only one CBLAS provider should be linked in a process. Run MKL and OpenBLAS in
separate invocations; TBLIS can be combined with either. GSL is tested separately
because its CBLAS headers/backend can conflict with another provider. In JSON,
context.interfaces records offered functions; inspect bound labels/generated C
to determine which functions actually ran. A TACO-only result is not evidence
that the selected external library executed.

For OpenBLAS, after setting R to the artifact root:

```sh
export INCLUDE_HEADERS='#include <cblas.h>'
export INCLUDE_PATH='' LIB_PATH=''
export DYNAMIC_LIB_FILES='-lopenblas -lm'
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
cd "$R/scripts/bench-scripts"
make run-multi-gemm DIMS=8 INTERFACES='openblas.*' REPETITIONS=2 OUT="$R/local-tests/openblas-smoke"
make draw-multi-gemm OUT="$R/local-tests/openblas-smoke"
```

For GSL, in a separate invocation:

```sh
export INCLUDE_HEADERS='#include <gsl/gsl_blas.h>
#include "gsl-wrappers.h"'
export INCLUDE_PATH="-I$R/tensor_algebra_systems_lib"
export LIB_PATH='' DYNAMIC_LIB_FILES='-lgsl -lgslcblas -lm'
export OMP_NUM_THREADS=1
cd "$R/scripts/bench-scripts"
make run-multi-gemm DIMS=8 INTERFACES='gsl.*' REPETITIONS=2 OUT="$R/local-tests/gsl-smoke"
make draw-multi-gemm OUT="$R/local-tests/gsl-smoke"
```

Use a fresh OUT for each run. The TBLIS/MKL setup is below under Reproducing the
environment. The existing Docker container already has the four CPU libraries;
these commands do not require downloading a replacement TBLIS version.

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

On DeltaAI, submit from the artifact root through the supplied batch script:

```sh
sbatch --account=YOUR_DELTA_ACCOUNT --export=ALL,DIMS=500,DENSITIES=0.1,REPETITIONS=3 \
  scripts/bench-scripts/multi-bench/deltaai-run.slurm gemm
```

The script requests one GPU for at most 45 minutes, builds on the compute node,
and calls the same Make target. Use `spmm` or `sddmm` as the final argument for
those kernels. It loads DeltaAI's CUDA/OpenBLAS/CMake modules; CUDA runtime and
math-library prefixes can differ in NVIDIA HPC SDK installations.
`CUDA_HOME`, `CUBLAS_ROOT`, `CUSPARSE_ROOT`, `OPENBLAS_ROOT`, and
`TBLIS_ROOT` override their respective installation prefixes.
The environment helper supports these prefixes without a separate execution
driver. A TBLIS selection requires an installed TBLIS prefix.

The batch output reports the result directory. After the job finishes, copy that
directory from your Mac terminal with `scp -r`, then run the plotting script
locally with `python3 scripts/bench-scripts/multi-bench/plot.py --kernel gemm --run
/absolute/path/to/copied-run`. Plotting needs Python and Matplotlib, not a GPU.
Use `sacct -j JOB_ID --format=JobID,State,Elapsed,AllocTRES` to inspect completion
and allocation; an SSH logout does not cancel a submitted batch job.

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

The fixed-width AVXSaxpy and TileSaxpy interfaces are excluded from this automatic
catalog: the matcher does not enforce their eight- and four-element contracts.
Their existing manually tiled benchmarks are separate from this workflow.

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
to request ten repetitions. The nine targets have separate main functions and
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
run before increasing sizes. CPU/header checks are not evidence of GPU
correctness or performance. Keep GPU validation logs with the source revision.

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
At the time of this October 30 audit, CUDA execution on Delta was unverified. AVX2 was
not runtime-tested. The updated Dockerfile was not rebuilt as a fresh image;
the Docker checks used installed dependencies and a separate source/build tree,
without replacing /mosaic-artifact in the existing container.

## Paper-library audit (November 2, 2026)

The existing linux/amd64 container has MKL 2020.4, GSL 2.7.1, OpenBLAS 0.3.20,
and the existing TBLIS installation. No library upgrade or download was needed.
Using the Make run/draw targets with dimension 8, density 0.25, two repetitions,
and one library thread passed nine configurations: all three kernels with
TBLIS+MKL, GSL, and OpenBLAS. The runs produced 34 schedule/configuration pairs
and 68 individual timing rows, with matching generated C files and PDF/HTML plots.

GEMM actually bound to TBLIS/MKL, GSL, and OpenBLAS in the respective runs.
SpMM bound only to MKL; the GSL/OpenBLAS SpMM runs and all SDDMM runs contained
only TACO schedules. GEMV/dot/TTV interfaces remain selectable, but were not
exercised as bindings in this audit. These checks establish workflow execution,
not numerical correctness or reproduction of the paper's results. No CUDA or
Stardust execution was performed.

## Additional kernel checks (November 2, 2026)

The new ttv, blockspmm, and spadd Make targets passed at dimension 3 with
densities 0, 0.25, and 1, two repetitions per schedule, and TBLIS/MKL offered.
They produced 24 schedule/configuration pairs and 48 timing rows, generated C,
and PDF/HTML plots. TTV bound to TBLIS; blockspmm and spadd produced TACO-only
schedules. A temporary independent scalar-reference check validated all 24
schedule/configuration pairs on separately generated inputs, twice each,
including the empty-input cases. The check is not part of measured benchmarks.
All nine executables rebuilt successfully. Six additional regression runs of
GEMM/SpMM/SDDMM (synthetic and the ds33.mtx fixture) passed after the shared result
allocation change. A Matrix Market request for TTV was rejected as intended.

## Integrated validation (November 9, 2026)

Mosaic revision 8da32ae8474ae203a42e44582529d491f80de9d1 and artifact revision
1617484 were validated together. The older audits above describe their earlier
snapshots, not the current SDDMM binding behavior.

- The ordinary Make run/draw workflow passed 31 CPU configurations: six synthetic
  kernels with four library selections, three Matrix Market cases, and four
  dimension/density combinations with folding disabled. These produced 1,339
  schedule/configuration pairs and 2,678 timing rows, with C files and plots.
  The five original GEMV benchmarks also passed at dimension 250.
- Seven CPU library checks compared rectangular products to scalar references,
  with two calls each: TBLIS GEMM/SDDMM, MKL GEMM/SpMM, GSL GEMM, and CBLAS GEMM
  using MKL and OpenBLAS providers in separate processes.
- A fresh recursive clone built the Docker image from the supplied Dockerfile.
  That final image passed 43 compiler/typed-fixture tests, five TBLIS/MKL library
  checks, and a normal dimension-32 GEMM run and plot. Dependency layers were
  cached; this was a fresh source build, not a claim of a no-cache image build.
- Native DeltaAI GH200 validation passed GEMM, SpMM, and SDDMM at dimension 500,
  density 0.1, three repetitions, and CUDA/OpenBLAS interfaces. The respective
  schedule counts were 6, 4, and 208. A dimension-250 GEMM run with folding off
  added 71 schedules. All four runs produced JSON and generated C; plotting
  was done locally after downloading the results.
- Delta also passed rectangular numerical checks for CUDA GEMM, CUDA SpMM,
  CUDA-bound SDDMM, OpenBLAS GEMM, and the nested-reduction lowering regression.
  The successful job used one GPU for 3m33s; including two failed setup attempts,
  total allocated GPU wall time was 5m49s. No validation jobs remained queued.

On the CPU GEMM-250 comparison, folding reduced 73 candidates to 8: unbound
candidates fell from 67 to 2, while the six bound candidates stayed present.
This is a search-space comparison, not a runtime speedup measurement. Structural
deduplication remains enabled when constant folding is disabled.

SDDMM now explicitly represents the inner reduction. At dimension 32 with TBLIS
and MKL offered, it returned 138 TACO candidates and 35 candidates for each of
TBLIS, CBLAS, and MKL. Delta returned 138 TACO, 35 CUDA, and 35 OpenBLAS candidates.
These counts include different rewrites; they are not counts of distinct library
functions or a guarantee of globally unique algorithms.

Limits: CPU Docker timings on Apple Silicon are emulated. CUDA adapter timings
include allocation, host/device transfers, synchronization, and cleanup, not
only device execution. The old Delta TBLIS installation was API-incompatible
with these legacy interfaces and was excluded; the standard Delta selection is
CUDA plus OpenBLAS. The optional CUDA Docker image was not tested. Successful
workflow runs and selected numerical regressions are bounded evidence, not
exhaustive validation of all generated schedules or format conversions.

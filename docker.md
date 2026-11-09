# Reproducible Mosaic benchmark container

## Build from this checkout

The Dockerfile builds the current artifact and Mosaic sources, including local
edits. Initialize submodules on a fresh checkout first. Do not reset an existing
modified Mosaic checkout just to build Docker.

```sh
# Only on a fresh clone:
git submodule update --init --recursive

# From the mosaic-artifact directory:
docker build --platform linux/amd64 --build-arg BUILD_JOBS=4 -t mosaic-benchmarks:local .
```

Required source files include the updated Mosaic compiler/interfaces, all nine
multi-benchmark files and their CMake targets, and the matching artifact wrappers.
The Dockerfile alone cannot add those changes to an older Mosaic revision.
Uninitialized submodules fail the build; no branch is silently fetched/reset.

This image installs MKL, OpenBLAS, GSL, TBLIS, Python plotting dependencies, and
Z3 for Mosaic's existing SMT code.
It builds taco-bench, taco-test, and all nine taco-multi-* executables with the
existing CMake targets. It does not replace Mosaic's matching, format conversion,
code generation, library interfaces, or benchmark timing.

The Ubuntu base is digest-pinned, APT packages come from the dated Ubuntu snapshot
in the Dockerfile, and TBLIS 1.3.0 is pinned to
c4f81e08b2827e72335baa7bf91a245f72c43970. TBLIS uses its supplied configure/make
build with pthreads and without its optional BLAS dependency, preventing accidental
OpenBLAS linkage when selecting MKL. Runtime CPU dispatch remains enabled; no
machine-specific -march=native flags are used. The bootstrap stage supplies only
TLS certificates; the final image's packages come from the snapshot.

Do not pass current TBLIS 2.x options (--enable-compat or BLIS_CONFIG_FAMILY) to
this 1.3.0 build. Updating the TBLIS revision requires revalidating the interfaces.

Old host builds, Git metadata, installed TBLIS binaries, and prior benchmark results
are excluded by .dockerignore. Source-file hashes, installed package versions,
TBLIS configuration, and build arguments are recorded in /opt/mosaic-build-info.
Keep the exact source checkout or a private source archive as well as the image.
A matching Dockerfile with different source edits is not the same experiment.

## Start, reopen, and stop

Run these on the Mac, not inside a container:

```sh
mkdir -p "$HOME/Desktop/research-workspace/benchmark-results/docker"
docker run -dit --platform linux/amd64 --name mosaic-research \
  --mount "type=bind,source=$HOME/Desktop/research-workspace/benchmark-results/docker,target=/results" \
  mosaic-benchmarks:local
docker exec -it mosaic-research bash
```

The container starts in /mosaic-artifact/scripts/bench-scripts. The entrypoint and
interactive Bash setup source the standard artifact environment script, defaulting
to TBLIS plus MKL. The entrypoint only configures environment variables and executes
your command; it is not a benchmark driver.

From a docker exec shell, exit returns to the Mac without stopping the container.
Later use docker exec -it mosaic-research bash again, or docker start mosaic-research
first if stopped. To stop it from the Mac: docker stop mosaic-research.
No --rm is used for the working container. Outputs under /results are already on
the Mac; no docker cp is needed.

## Run and plot

Inside the container:

```sh
source /mosaic-artifact/scripts/mosaic_env_var.sh tblis,mkl
cd "$PATH_TO_MOSAIC_ARTIFACT/scripts/bench-scripts"
make list-multi-interfaces
OUT="/results/spmm-$(date +%Y%m%d-%H%M%S)"
make run-multi-spmm INPUT=synthetic DIMS=250 DENSITIES=0.1 \
  INTERFACES='tblis.*,mkl.*' REPETITIONS=10 CONSTANT_FOLDING=true WARMUP=0 OUT="$OUT"
make draw-multi-spmm OUT="$OUT"
```

Results are in $OUT/0/results.json, $OUT/0/code/schedule*.c, and
$OUT/0/plots/schedules.pdf (also schedules.html). Each dimension/density pair
gets a numbered directory. Always choose a new OUT for a new run.

Library environment selection and interface selection have different jobs:

```sh
source /mosaic-artifact/scripts/mosaic_env_var.sh taco
source /mosaic-artifact/scripts/mosaic_env_var.sh tblis
source /mosaic-artifact/scripts/mosaic_env_var.sh tblis,mkl
source /mosaic-artifact/scripts/mosaic_env_var.sh tblis,openblas
source /mosaic-artifact/scripts/mosaic_env_var.sh gsl
```

Each source command replaces the preceding header/link configuration.
Matteo's configure_mosaic_system shell function is also available after sourcing;
its blas/dot_blas/gemv_blas names select OpenBLAS. Library adapters stay in their
existing wrapper headers, not inline C functions inside environment variables.
Use the one appropriate to the next run, not all five. The script is for Bash
on Linux (Bash 4+), not macOS's stock Bash 3.2 or zsh. It sets the existing
INCLUDE_HEADERS, INCLUDE_PATH, LIB_PATH, and DYNAMIC_LIB_FILES variables.
INTERFACES offers functions to autoAccelerate; it does not configure the linker
or guarantee that a function matches. Do not combine MKL, GSL, and OpenBLAS as
CBLAS providers in one process. TBLIS can be combined with any one of them.

The default is one thread per library. Override OMP_NUM_THREADS, MKL_NUM_THREADS,
TBLIS_NUM_THREADS, and OPENBLAS_NUM_THREADS explicitly for other experiments.
MKL uses the LP64 sequential runtime, not hardcoded AVX2 implementation libraries.
AMD64 Docker on Apple Silicon uses emulation: these are not native CPU timings.

Noninteractive docker exec does not run the image's entrypoint. Source the
environment explicitly in each such command:

```sh
docker exec mosaic-research bash -lc '
  source /mosaic-artifact/scripts/mosaic_env_var.sh tblis,mkl
  cd "$PATH_TO_MOSAIC_ARTIFACT/scripts/bench-scripts"
  make list-multi-interfaces
'
```

## Check a fresh build

From the Mac:

```sh
docker exec mosaic-research bash /mosaic-artifact/scripts/docker-smoke.sh \
  "/results/smoke-$(date +%Y%m%d-%H%M%S)"
```

This uses the ordinary Make run/draw workflow: six synthetic kernels across four
CPU configurations, three Matrix Market cases, and a dimension/density sweep
with folding disabled. It also runs the five original GEMV benchmarks at dimension
250. It checks JSON timing rows, generated C, plots, and actual
dense GEMM library bindings, and runs the focused existing compiler regressions.
It is not a comprehensive numerical or performance validation.

The pre-existing figure benchmarks are also built. Their shell scripts' systems
lists and plotting lists must still agree with your selected library environment.
Some legacy kernels/interfaces have known compiler or adapter limitations; an
installed library is not proof every historical figure succeeds. See the
multi-bench README for supported contracts and exclusions.

## Optional CUDA image

The same Dockerfile accepts a CUDA 12.6 development base on an x86-64 NVIDIA host:

```sh
docker build --platform linux/amd64 --build-arg WITH_CUDA=true \
  --build-arg BASE_IMAGE=nvidia/cuda:12.6.3-devel-ubuntu22.04@sha256:d49bb8a4ff97fb5fe477947a3f02aa8c0a53eae77e11f00ec28618a0bcaa2ad1 \
  -t mosaic-benchmarks:cuda .
docker run --gpus all -it --name mosaic-cuda \
  -e MOSAIC_LIBRARIES=tblis,mkl,cuda mosaic-benchmarks:cuda
```

This requires the host NVIDIA driver and NVIDIA Container Toolkit. The base
supplies cuBLAS, cuSPARSE, and CUDA headers/libraries. The environment script
supports cuda, cublas, and cusparse, optionally combined with CPU libraries.
These are the existing Mosaic host-C adapters; no custom GPU driver or alternate
compiler path is added, and CMake -DCUDA=ON is not needed for these adapters.

CUDA is not executable on the Mac. This x86 image must not be used as a native
performance environment on DeltaAI's ARM Grace nodes. There, build natively with
the site CUDA module and omit x86-only MKL, following the existing Delta workflow.
GPU execution and this optional image variant must be verified on the target
machine; CPU-container tests do not validate CUDA.

On November 9, native DeltaAI CUDA/OpenBLAS GEMM, SpMM, and SDDMM runs passed at
dimension 500, with separate rectangular numerical checks. This validates the
native site-module workflow, not the optional x86 CUDA image above. Delta's old
TBLIS installation was incompatible with the legacy TBLIS interface and was not
included. See the multi-bench README for the exact validation scope.

Unavailable/unsafe legacy interfaces (for example the existing MKL sparse-add
adapter), fixed-width AVX/tile bindings without enforced shape constraints,
Apple Accelerate on Linux, and the separate Stardust simulator are not made
working merely by installing packages. Their exclusions remain intentional.

## Preserve an exact image

From the Mac, after building:

```sh
docker image inspect mosaic-benchmarks:local --format '{{.Id}}'
docker image save mosaic-benchmarks:local | gzip > mosaic-benchmarks-image.tar.gz
shasum -a 256 mosaic-benchmarks-image.tar.gz
# Restore without downloading or rebuilding:
docker image load < mosaic-benchmarks-image.tar.gz
```

Retain the source archive and image together in private off-machine storage.
The earlier full-container backup is separate and remains unchanged. Fresh
source builds reproduce the environment and workflow, not bit-identical random
inputs, timings, or build timestamps. Refresh the pinned snapshot deliberately
for security updates and rerun validation.

References: [Ubuntu snapshots](https://snapshot.ubuntu.com/) and
[NVIDIA container requirements](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/sample-workload.html).

## Last verified CPU image

The November 9 build used artifact 1617484 with Mosaic
8da32ae8474ae203a42e44582529d491f80de9d1 from a fresh recursive clone. It produced
image sha256:7d42c157bdca00b6b1ef9c707e933929d03ce5209481c994fa39d3c475daaeb7,
locally tagged mosaic-benchmarks:meeting-20261109. The image passed 43 focused
compiler/typed-fixture tests, five TBLIS/MKL numerical checks, and the normal
GEMM run/draw workflow. It has not been published to a container registry.
Later documentation-only commits do not change that recorded build provenance.






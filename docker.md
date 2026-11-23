## Getting Started with Docker
The following instructions only apply if you are not working on our AWS machine.


- Download this repository and run the following commands to build and attach a docker image from the provided Dockerfile.


 ```
 git clone <link to this repo>
 git submodule update --init --recursive
 docker build -t mosaic-artifact .
 ```


- Once the image is built, run a docker container with a bash terminal
 ```
 docker run -d -it --rm mosaic-artifact bash
 ```
- The above command should print out a `CONTAINER_ID`. Attach to the
 docker container using the command below and the `CONTAINER_ID` from the
 previous step.
 ```
 docker attach <CONTAINER_ID>
 ```


 *Note:* Do not type `exit` in the docker terminal as this will kill the container. The proper way to exit the docker is the sequence `CTRL-p, CTRL-q`.


- Download the external functions that can be run on your machine. Refer to the [Downloading External Functions](#downloading-external-functions) section to learn more about which machines each library can be run on and how to download these functions with our provided scripts.


## Installing TBLIS

TBLIS is built during `docker build` by `scripts/tblis_download.sh` and installed
under `/mosaic-artifact/tensor_algebra_systems_lib/tblis`.

## Running cuBLAS

The image installs CUDA 13.1 and the cuBLAS and cuSPARSE development libraries from the Ubuntu 26.04 package archive. The host
needs a compatible NVIDIA driver and the
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
configured for Docker. Start the container with GPU access:

```bash
docker run --rm -it --gpus all mosaic-artifact bash
```

Inside the container, select the cuBLAS provider before launching code that
uses cuBLAS:

```bash
source /mosaic-artifact/scripts/mosaic_env_var.sh cublas
```

Building the image does not require a GPU. Running cuBLAS does; the container
uses the host's NVIDIA driver.

## Running cuSPARSE SpMV

The image includes cuSPARSE and checks that the Mosaic wrapper compiles and
links during the build. Start the container with `--gpus all` as above. Inside
the container, run the correctness test and a benchmark case with:

```bash
cd /mosaic-artifact
source scripts/mosaic_env_var.sh cusparse
mosaic/build/bin/taco-test --gtest_filter=interface.cudaSparseGemv
mosaic/build/bin/taco-bench --benchmark_filter='^bench_spmv_cuda/250/'
```

`cuda` is an alias for the `cusparse` provider. The benchmark measures the
complete FP32 CSR matrix–vector multiply, including device allocation and
host–device transfers on every call.

## Testing GPU SDDMM across sparsities

In a rebuilt image started with `--gpus all`, `run-fig16` runs the cuSPARSE
benchmark and the optimized CUDA kernel. Each can also be run separately.

```bash
make -C /mosaic-artifact/scripts/bench-scripts run-sddmm-varsparsity-cusparse
make -C /mosaic-artifact/scripts/bench-scripts run-sddmm-varsparsity-cuda
make -C /mosaic-artifact/scripts/bench-scripts draw-fig16
```

Both benchmarks run FP32 CSR SDDMM at the eight Figure 16 densities with
2,000 × 2,000 matrices. They write Google Benchmark JSON to
`scripts/bench-scripts/sddmm_varSparsity/result/` under `cusparse` and
`cuda_optimized`, and the plot includes each series when its results are
present. Timings include the call or kernel launch and synchronization.
Allocation, transfers, preprocessing, and sampled numerical checks run outside
the timed region. Enable the native targets with `-DMOSAIC_CUSPARSE_SDDMM=ON`
and `-DMOSAIC_CUDA_SDDMM=ON`, respectively.

## Running SuiteSparse SDDMM

Rebuild the benchmark binaries, then run the SuiteSparse sweep from the
artifact root.

```bash
make -C scripts/bench-scripts run-sddmm-suitesparse
```

This reads all five checked-in SuiteSparse lists, caches Matrix Market files
under `mosaic-benchmarks/data/suitesparse`, and writes
`scripts/bench-scripts/sddmm_suitesparse/result/timings.csv`. Each distinct
matrix is timed once per built backend and appears in the CSV at its position
in every list that contains it. The matrix's nonzero pattern forms the binary
mask. The dense operands use an inner dimension of 100 and FP32 values.

To try one matrix per list on the CPU, or to run against a local matrix cache:

```bash
make -C scripts/bench-scripts run-sddmm-suitesparse \
    SUITESPARSE_ARGS="--limit 1 --backend cpu_blocked"
make -C scripts/bench-scripts run-sddmm-suitesparse \
    SUITESPARSE_ARGS="--offline --matrix-dir /path/to/matrix-cache"
```

The local cache accepts `NAME.mtx` or `NAME/NAME.mtx`. Use `--list` to select
individual list files and `--output` to save runs to separate CSVs.

The Docker image also builds the official BSMR-SDDMM implementation at a
pinned revision. To run just this backend inside a GPU-enabled container
with the matrix cache and results directory mounted:

```bash
make -C /mosaic-artifact/scripts/bench-scripts run-sddmm-mosaic-paper \
    'SUITESPARSE_ARGS=--matrix-dir /matrices --offline --backend bsmr --output /results/mosaic-paper-bsmr.csv'
```

BSMR pads the 100-element reduction to 128 with zeros for its CUDA kernels.
Its dense tiles use TF32 Tensor Cores and its sparse tiles use FP32 CUDA
cores. The benchmark times the upstream launch and synchronization, including
its stream and event overhead. Matrix reordering and transfers are outside
the timed region.

The `sampled_gsl` backend calls `gsl_blas_sdot` once per stored entry.
To compare it with the existing GSL GEMV backend on the cached paper matrices:

```bash
make -C scripts/bench-scripts run-sddmm-mosaic-paper \
    SUITESPARSE_ARGS="--offline --matrix-dir $PWD/suitesparse-cache --backend sampled_gsl --backend gemv_gsl --output /tmp/sddmm-gsl.csv"
```

The MKL backends (`mkl`, `dot_mkl`, and `gemv_mkl`) use the dedicated
`taco-bench-suitesparse-mkl` executable. Set `MKL_NUM_THREADS` in the
environment to choose the thread count. The Docker image builds this target
with `MOSAIC_SUITESPARSE_LIBRARIES=ON`.

With the six paper matrices cached in `suitesparse-cache/`, run the MKL
backends at one and four threads from the artifact root:

```bash
mkdir -p suitesparse-results
for threads in 1 4; do
    docker --context rootless run --rm \
        -e "MKL_NUM_THREADS=$threads" -e MKL_DYNAMIC=FALSE \
        -v "$PWD/suitesparse-cache:/matrices:ro" \
        -v "$PWD/suitesparse-results:/results" \
        mosaic-artifact make -C /mosaic-artifact/scripts/bench-scripts run-sddmm-mosaic-paper \
        "SUITESPARSE_ARGS=--matrix-dir /matrices --offline --backend mkl --backend dot_mkl --backend gemv_mkl --output /results/mosaic-paper-mkl-${threads}t.csv"
done
```

To run the rectangular SGEMM regression inside the image:

```bash
docker --context rootless run --rm mosaic-artifact \
    ctest --test-dir /mosaic-artifact/mosaic/build -R suitesparse-mkl-lp_nug08 -V
```

## Adding Additional Libraries
### Downlaoding CPU External Functions


We provide a list of external functions that can be downloaded on a CPU and which machines they are compatible with. We also provide scripts to download and build each library. We also note any performance-related quirks related to some functions (for example, the tuning time of ATLAS).


We provide a list of known issues. Please note that this list may be not comprehensive and is based on our experience. The authors are not experts on these external systems.

CBLAS, MLK, GSL have already been added for convenience. 


| Library | Known Issues | Download Instructions | Time Taken to Complete |
| ------ | ------ | ------ | ------ |
| CBLAS                   | Will need to include \<Accelerate/Accelerate.h\> on Macs | For ubuntu: ```sudo apt-get install openblas``` | 5 minutes|
| MKL + AVX               | M1 machines will emulate these functions and performance suffers| For ubuntu: ```sudo apt-get install libmkl-dev libmkl-avx2``` | 5 minutes |
| TBLIS                   | Could not successfully compile with clang | ```./scripts/tblis_download.sh``` | 20 Minutes|
| GSL + Tensor  Extension + (optional) ATLAS || ```./scripts/gsl_download.sh``` | 4 minutes (GSL) + 2 minutes (Tensor Extension) + (optional ~8 hours ATLAS)|
| AVX | On x86 machines only| | Should be downloaded with MKL|


Please note that we provide the quickest build for ATLAS without any additional
passed in using ```sudo apt-install libatlas-base-dev```. We provide an ```atlas_download.sh``` script
that can be used to link against the tuned version. To run this and download
GSL again, uncomment the ```./atlas_download.sh``` line in
```scripts/gsl_download.sh```.


### Linking External Functions


To link against the systems that were downloaded, you will need to modify the variables in ```scripts/mosaic_env_var.sh```. The default settings select the system-installed OpenBLAS.


- To add the path for the headers of the library, modify the ```INCLUDE_PATH``` variable.
- To add the path for the shared object file of the library, modify the ```LIB_PATH``` variable. To add this path to the runtime linking path, use the ```-Wl-R``` flag. Modify the ```DYNAMIC_LIB_FILES``` variable to actually link against the library.
- To add the ```#include <header>.h``` to the code that Mosaic generates, modify the ```INCLUDE_HEADERS``` variable.




## Running Benchmarks


To run a specific benchmark, run:


 ```
 make run-fig<#>
 ```


To make a specific figure (assuming the data has been generated using the previous command), run:


 ```
 make draw-fig<#>
 ```


For example, if you want to run and draw fig13, you will run ```make run-fig13 && make draw-fig13```.


However, you may need to specify a subset of external systems to run for the benchmark. To change the external functions that the benchmark uses, change the
```systems``` variable in the ```bench.sh``` file. The ```bench.sh``` is located inside the folder for a specific benchmark.


For example, if you want to limit the GEMV benchmark to run using only ```mkl``` and ```blas``` change the ```systems``` variable to:


 ```
   systems=("blas" "mkl")
 ```


To plot only these two systems, also change the ```--systems``` argument used in the ```draw-fig13``` rule in the Makefile to ```--systems=mkl,blas```.




## General Docker Functionality

  - List all docker images
    `docker images`


  - Remove docker image
    `docker image rm IMAGE`


  - List all (stopped and running) docker containers
    `docker ps -a`


  - Stop one or more running containers
    `docker stop CONTAINERS`


  - Remove stopped docker container
    `docker rm CONTAINERS`






## Select the kernel environment per test

The configuration contains variable assignments and a `case` statement, with no
function definitions. Select a provider explicitly for a direct benchmark run:

```bash
source scripts/mosaic_env_var.sh tblis
"$PATH_TO_MOSAIC_ARTIFACT/mosaic/build/bin/taco-bench" --benchmark_filter='^bench_gemv_tblis/'

source scripts/mosaic_env_var.sh blas
"$PATH_TO_MOSAIC_ARTIFACT/mosaic/build/bin/taco-bench" --benchmark_filter='^bench_gemv_blas/'
```

Supported selections are `blas` (also `openblas`), `tblis`, `mkl`, `gsl`, `cublas`, `cuda`,
`taco`, and `stardust`. Benchmark variants such as `dot_mkl`, `gemv_gsl`,
`bug_mkl`, and `gemv_blas` select the corresponding provider automatically.
Each selection resets `INCLUDE_PATH`, `LIB_PATH`, `DYNAMIC_LIB_FILES`, and
`INCLUDE_HEADERS`. Edit that provider's assignments for nonstandard installations.
Libraries must still be installed; CUDA needs its toolkit and GPU setup.

The environment must be selected before launching `taco-bench`: generated-code
headers are captured when the process starts. For mixed-provider unit tests,
run separate provider-specific test processes with matching filters.

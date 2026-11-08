## Use the Makefile with Docker

Initialize the source submodules and build the image:

```bash
git submodule update --init --recursive
docker build -t mosaic-artifact .
```

The Dockerfile installs MKL, GSL, OpenBLAS, Python plotting/data packages, and Z3
directly, then runs `scripts/tblis_download.sh` to build the pinned TBLIS version.
Both `taco-bench` and `taco-test` are built.

Start the container with:

```bash
docker run --name mosaic-shell -it \
  -w /mosaic-artifact/scripts/bench-scripts mosaic-artifact bash
```

The interactive shell loads the default OpenBLAS environment. Figure 13 (GEMV)
runs and plots only the `blas` provider. Other benchmark
providers still need their corresponding header and linker settings; installation
alone does not configure every runner. CUDA runs require a separately configured
CUDA toolkit and GPU-enabled container. Stardust uses the repository's recorded data.

To copy a generated PDF back to the host, replace `<filename>` in:

```bash
docker cp mosaic-shell:/mosaic-artifact/scripts/bench-scripts/figs/<filename>.pdf ./<filename>.pdf
```

Existing figure PDFs are copied from the repository when the image is built;
their presence does not mean the benchmarks have run.
The additional-library instructions below are for other figures and workflows.

## Run GEMV with OpenBLAS

In the container:

```bash
source /mosaic-artifact/scripts/mosaic_env_var.sh
cd "$PATH_TO_MOSAIC_ARTIFACT/scripts/bench-scripts"
make run-fig13
make draw-fig13
```

By default, the environment inserts `cblas.h` into generated C and links kernels
with `-lopenblas`. Each figure runner sources the environment again with its
current `systems` entry before launching a separate benchmark process. The existing `bench_gemv_blas` implementation maps matrix-vector
multiplication to `CblasGemv`; no new compiler interface is required. The plot is
written to `scripts/bench-scripts/figs/fig13.pdf`.

When sourced from Bash outside Docker, the environment script infers the checkout
root unless `PATH_TO_MOSAIC_ARTIFACT` is already set. A local run also requires
OpenBLAS development files and a built `mosaic/build/bin/taco-bench`.

Only the GEMV figure workflow has been restricted to OpenBLAS. Other figures and
the full unit suite still require their providers' environment settings. TBLIS
is still installed by the Dockerfile, but is no longer the default kernel library.

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

## Adding Additional Libraries
### Downlaoding CPU External Functions


We provide a list of external functions that can be downloaded on a CPU and which machines they are compatible with. We also provide scripts to download and build each library. We also note any performance-related quirks related to some functions (for example, the tuning time of ATLAS).


We provide a list of known issues. Please note that this list may be not comprehensive and is based on our experience. The authors are not experts on these external systems.




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

Supported selections are `blas` (also `openblas`), `tblis`, `mkl`, `gsl`, `cuda`,
`taco`, and `stardust`. Benchmark variants such as `dot_mkl`, `gemv_gsl`,
`bug_mkl`, and `gemv_blas` select the corresponding provider automatically.
Each selection resets `INCLUDE_PATH`, `LIB_PATH`, `DYNAMIC_LIB_FILES`, and
`INCLUDE_HEADERS`. Edit that provider's assignments for nonstandard installations.
Libraries must still be installed; CUDA needs its toolkit and GPU setup.

The environment must be selected before launching `taco-bench`: generated-code
headers are captured when the process starts. For mixed-provider unit tests,
run separate provider-specific test processes with matching filters.

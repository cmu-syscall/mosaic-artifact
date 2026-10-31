## Run Fig. 19 automatically

Initialize the source submodules, build the image, then start it:

```bash
git submodule update --init --recursive
docker build -t mosaic-artifact .
docker run --name mosaic-fig19 mosaic-artifact
```

The image installs MKL, GSL, OpenBLAS, plotting dependencies, and a pinned TBLIS
revision. Its default startup command is `make run-fig19`, executed from
`/mosaic-artifact/scripts/bench-scripts`. No dependency installation or environment
sourcing is needed after startup. The complete benchmark can take several minutes.

To also draw the PDF at startup and copy it back after the run:

```bash
docker run --name mosaic-fig19-plot mosaic-artifact \
  bash -c 'make run-fig19 && make draw-fig19'
docker cp mosaic-fig19-plot:/mosaic-artifact/scripts/bench-scripts/figs/fig19.pdf ./fig19.pdf
```

For an interactive shell instead, override the default command with
`docker run --rm -it mosaic-artifact bash`.
The image builds `taco-bench`; other compiler targets can be built separately.
The additional-library instructions below are for other figures and workflows.

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


## Testing Functionality.


To test basic functionality, in the ```scripts/bench-scripts/``` directory run:


```
 make run-tblis-tests
```


This will download the TBLIS source code in ```tensor_algebra_systems_src```, build from source and place the resultant dynamic libraries in ```tensor_algebra_systems_lib```. It will also run tests that target the TBLIS external library.


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


To link against the systems that were downloaded, you will need to modify the variables in ```scripts/bench-scripts/mosaic_env_var.sh```. An example has already been included for TBLIS.


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






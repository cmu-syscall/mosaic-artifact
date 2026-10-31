FROM docker.io/ubuntu:26.04
LABEL description="mosaic-artifact"

ENV DEBIAN_FRONTEND=noninteractive
# BLIS does not recognize Ubuntu's cc version banner; select gcc explicitly.
ENV CC=gcc CXX=g++
# Older downloaded GoogleTest releases need this policy floor with CMake 4.
ENV CMAKE_POLICY_VERSION_MINIMUM=3.10
ENV PATH_TO_MOSAIC_ARTIFACT=/mosaic-artifact
ENV INCLUDE_HEADERS="" MPLBACKEND=Agg
ARG BUILD_JOBS=2
ARG TBLIS_REVISION=eb719e718976572e0ab53975f4e0c799faeb35f2

RUN apt-get update
RUN apt-get install -y build-essential ca-certificates wget curl git
RUN apt-get install -y cmake pkg-config
RUN apt-get install -y python3 python3-dev python3-numpy python3-scipy python3-pandas python3-matplotlib
RUN apt-get install -y libmkl-dev libgsl-dev libopenblas-dev
RUN apt-get install -y graphviz xxd time vim texinfo libtool-bin bzip2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Build the same TBLIS revision that passed Fig. 19 in the repaired container.
# Keep dependency builds separate from Mosaic's LIB_PATH environment settings.
RUN git clone https://github.com/devinamatthews/tblis.git /opt/tblis-src
RUN git -C /opt/tblis-src checkout "${TBLIS_REVISION}"
RUN git -C /opt/tblis-src submodule update --init --recursive
RUN env -u LIB_PATH cmake -S /opt/tblis-src -B /opt/tblis-build \
    -DCMAKE_C_COMPILER=/usr/bin/gcc \
    -DCMAKE_CXX_COMPILER=/usr/bin/g++ \
    -DCMAKE_INSTALL_PREFIX=/mosaic-artifact/tensor_algebra_systems_lib/tblis \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBLIS_CONFIG_FAMILY=generic \
    -DBLIS_THREAD_MODEL=pthread
RUN env -u LIB_PATH cmake --build /opt/tblis-build --parallel "${BUILD_JOBS}"
RUN env -u LIB_PATH cmake --install /opt/tblis-build

COPY . /mosaic-artifact
RUN mkdir -p /temp /mosaic-artifact/tensor_algebra_systems_src
RUN chmod +x /mosaic-artifact/scripts/bench-scripts/sddmm/bench.sh
RUN cmake -S /mosaic-artifact/mosaic -B /mosaic-artifact/mosaic/build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.10 \
    -DGIT_SUBMODULE=OFF \
    -DBENCHMARK_DOWNLOAD_DEPENDENCIES=ON \
    -DBENCHMARK_ENABLE_TESTING=OFF
RUN cmake --build /mosaic-artifact/mosaic/build --target taco-bench --parallel "${BUILD_JOBS}"

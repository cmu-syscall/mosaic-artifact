FROM docker.io/ubuntu:26.04
LABEL description="mosaic-artifact"

ENV DEBIAN_FRONTEND=noninteractive
# GCC 13 supports the Knights Landing flags used by the pinned TBLIS version.
ENV CC=gcc-13 CXX=g++-13
# Older downloaded GoogleTest releases need this policy floor with CMake 4.
ENV CMAKE_POLICY_VERSION_MINIMUM=3.10
ENV PATH_TO_MOSAIC_ARTIFACT=/mosaic-artifact
ENV INCLUDE_HEADERS="" MPLBACKEND=Agg
ARG BUILD_JOBS=2

RUN apt-get update
RUN apt-get install -y build-essential gcc-13 g++-13 ca-certificates wget curl git
RUN apt-get install -y cmake pkg-config
RUN apt-get install -y python3 python3-dev python3-numpy python3-scipy python3-pandas python3-matplotlib python3-z3
RUN apt-get install -y libmkl-dev libgsl-dev libopenblas-dev
RUN apt-get install -y graphviz xxd time vim texinfo libtool-bin bzip2 autoconf automake

SHELL ["/bin/bash", "-o", "pipefail", "-c"]


COPY . /mosaic-artifact
RUN mkdir -p /temp /mosaic-artifact/tensor_algebra_systems_src
RUN source /mosaic-artifact/scripts/mosaic_env_var.sh && \
    mkdir -p "$TENSOR_ALGEBRA_SRC" "$TENSOR_ALGEBRA_LIB" && \
    env -u LIB_PATH bash -e /mosaic-artifact/scripts/tblis_download.sh
RUN python3 -c 'import numpy, scipy, pandas, matplotlib, z3'
RUN echo "source /mosaic-artifact/scripts/mosaic_env_var.sh" >> /root/.bashrc
RUN cmake -S /mosaic-artifact/mosaic -B /mosaic-artifact/mosaic/build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.10 \
    -DGIT_SUBMODULE=OFF \
    -DBENCHMARK_DOWNLOAD_DEPENDENCIES=ON \
    -DBENCHMARK_ENABLE_TESTING=OFF
RUN cmake --build /mosaic-artifact/mosaic/build --target taco-bench taco-test --parallel "${BUILD_JOBS}"

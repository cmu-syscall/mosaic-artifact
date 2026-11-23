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

RUN apt-get install -y --no-install-recommends cuda-compiler-13-1 \
    cuda-cudart-dev-13-1 libcublas-dev-13-1 libcusparse-dev-13-1
ENV NVIDIA_VISIBLE_DEVICES=all NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV CUDAToolkit_ROOT=/usr/local/cuda
RUN test -x /usr/local/cuda/bin/nvcc && \
    echo /usr/local/cuda/lib64 > /etc/ld.so.conf.d/cuda.conf && ldconfig && \
    printf '#include <cublas_v2.h>\nint main(void) { cublasHandle_t h; return cublasCreate(&h); }\n' | \
    gcc-13 -x c - -I/usr/local/cuda/include -L/usr/local/cuda/lib64 -lcublas -o /tmp/cublas-link-check && \
    rm /tmp/cublas-link-check

SHELL ["/bin/bash", "-o", "pipefail", "-c"]


COPY . /mosaic-artifact
RUN printf '#include "cuda-wrappers.h"\nvoid check(const taco_tensor_t *a, const float *x, float *y, int rows) { cuda_spmv(a, x, y, rows); }\n' | \
    gcc-13 -std=c99 -shared -fPIC -Wl,-z,defs -x c - \
      -isystem /usr/local/cuda/include -I/mosaic-artifact/mosaic/include \
      -I/mosaic-artifact/tensor_algebra_systems_lib -L/usr/local/cuda/lib64 \
      -lcudart -lcusparse -o /tmp/cusparse-link-check.so && \
    rm /tmp/cusparse-link-check.so
RUN mkdir -p /temp /mosaic-artifact/tensor_algebra_systems_src
RUN source /mosaic-artifact/scripts/mosaic_env_var.sh && \
    mkdir -p "$TENSOR_ALGEBRA_SRC" "$TENSOR_ALGEBRA_LIB" && \
    env -u LIB_PATH bash -e /mosaic-artifact/scripts/tblis_download.sh
RUN git clone https://github.com/zhtvk/tensor.git /tmp/tensor-extension && \
    mkdir -p /tmp/tensor-extension/build && \
    cd /tmp/tensor-extension/build && \
    ../configure \
      --prefix=/mosaic-artifact/tensor_algebra_systems_lib/tensor && \
    make -j"${BUILD_JOBS}" && \
    make install && \
    test -f /mosaic-artifact/tensor_algebra_systems_lib/tensor/include/tensor/tensor_float.h
RUN python3 -c 'import numpy, scipy, pandas, matplotlib, z3'
RUN echo "source /mosaic-artifact/scripts/mosaic_env_var.sh" >> /root/.bashrc
RUN cmake -S /mosaic-artifact/mosaic -B /mosaic-artifact/mosaic/build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.10 \
    -DGIT_SUBMODULE=OFF \
    -DMOSAIC_CUSPARSE_SDDMM=ON \
    -DMOSAIC_CUDA_SDDMM=ON \
    -DMOSAIC_SUITESPARSE_LIBRARIES=ON \
    -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
    -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-13 \
    -DBENCHMARK_DOWNLOAD_DEPENDENCIES=ON \
    -DBENCHMARK_ENABLE_TESTING=OFF
RUN cmake --build /mosaic-artifact/mosaic/build --target taco-bench taco-test \
    taco-bench-sddmm-cusparse taco-bench-sddmm-cuda taco-bench-suitesparse-mkl --parallel "${BUILD_JOBS}"

# Build the SuiteSparse BSMR backend against the official research artifact.
RUN apt-get install -y --no-install-recommends libcurand-dev-13-1
RUN git init -q /tmp/bsmr-sddmm && \
    git -C /tmp/bsmr-sddmm fetch --depth=1 https://github.com/CX9898/BSMR-SDDMM.git 2072fd187688242c978f4a452ee3ff255e4c28d7 && \
    git -C /tmp/bsmr-sddmm checkout -q --detach FETCH_HEAD && \
    git -C /tmp/bsmr-sddmm apply /mosaic-artifact/scripts/bench-scripts/sddmm_suitesparse/bsmr/kernel-launch.patch
RUN cmake -S /mosaic-artifact/mosaic -B /mosaic-artifact/mosaic/build \
    -DMOSAIC_BSMR_SOURCE=/tmp/bsmr-sddmm "-DMOSAIC_BSMR_CUDA_ARCHITECTURES=89;120" && \
    cmake --build /mosaic-artifact/mosaic/build --target taco-bench-suitesparse-bsmr --parallel "${BUILD_JOBS}"

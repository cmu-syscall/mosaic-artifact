ARG BASE_IMAGE=ubuntu:22.04@sha256:076e7bf82319619f28dd0aa9c02ab34b055ad37100395b4f49a2ffba04fb5e11
FROM ${BASE_IMAGE} AS certificates
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates

FROM ${BASE_IMAGE}
ARG BASE_IMAGE
LABEL description="Mosaic compiler and multi-schedule benchmarking environment"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG BUILD_JOBS=4
ARG UBUNTU_SNAPSHOT=20261101T000000Z
ARG TBLIS_REVISION=c4f81e08b2827e72335baa7bf91a245f72c43970
ARG WITH_CUDA=false
ENV DEBIAN_FRONTEND=noninteractive CC=gcc CXX=g++ \
    PATH_TO_MOSAIC_ARTIFACT=/mosaic-artifact MPLBACKEND=Agg \
    MOSAIC_LIBRARIES=tblis,mkl

COPY --from=certificates /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
RUN test "$(dpkg --print-architecture)" = amd64 && \
    . /etc/os-release && test "$VERSION_ID" = 22.04 && \
    rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources && \
    printf 'deb [check-valid-until=no] https://snapshot.ubuntu.com/ubuntu/%s/ %s main restricted universe multiverse\n' \
        "$UBUNTU_SNAPSHOT" jammy "$UBUNTU_SNAPSHOT" jammy-updates \
        "$UBUNTU_SNAPSHOT" jammy-security > /etc/apt/sources.list && \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates cmake git curl wget pkg-config \
        autoconf automake libtool-bin texinfo bzip2 xxd time vim graphviz \
        python3 python3-numpy python3-scipy python3-pandas python3-matplotlib \
        libmkl-dev libgsl-dev libopenblas-dev && \
    rm -rf /var/lib/apt/lists/*

RUN case "$WITH_CUDA" in \
      false) ;; \
      true) test -f /usr/local/cuda/include/cuda_runtime_api.h && \
            test -f /usr/local/cuda/include/cublas_v2.h && \
            test -f /usr/local/cuda/include/cusparse.h ;; \
      *) exit 2 ;; \
    esac

RUN git clone https://github.com/MatthewsResearchGroup/tblis.git /opt/tblis-src && \
    git -C /opt/tblis-src checkout --detach "$TBLIS_REVISION" && \
    git -C /opt/tblis-src submodule update --init --recursive && \
    cd /opt/tblis-src && \
    env -u INCLUDE_HEADERS -u INCLUDE_PATH -u LIB_PATH -u DYNAMIC_LIB_FILES \
        ./configure --prefix=/mosaic-artifact/tensor_algebra_systems_lib/tblis \
        --enable-thread-model=pthreads --disable-static --without-blas && \
    make -j"$BUILD_JOBS" && make install && \
    mkdir -p /opt/mosaic-build-info && \
    git rev-parse HEAD > /opt/mosaic-build-info/tblis-revision.txt && \
    cp config.log /opt/mosaic-build-info/tblis-config.log && \
    make clean

RUN apt-get update && apt-get install -y --no-install-recommends python3-z3 && \
    rm -rf /var/lib/apt/lists/*

COPY mosaic/ /mosaic-artifact/mosaic/
WORKDIR /mosaic-artifact
RUN test -f mosaic/bench/benchmark/CMakeLists.txt && \
    test -f mosaic/python_bindings/pybind11/CMakeLists.txt && \
    cmake -S mosaic -B mosaic/build -DCMAKE_BUILD_TYPE=Release \
        -DGIT_SUBMODULE=OFF -DBENCHMARK_ENABLE_TESTING=OFF \
        -DBENCHMARK_DOWNLOAD_DEPENDENCIES=OFF && \
    cmake --build mosaic/build --parallel "$BUILD_JOBS" --target \
        taco-bench taco-test taco-multi-gemm taco-multi-spmm taco-multi-sddmm \
        taco-multi-suitesparse-gemm taco-multi-suitesparse-spmm \
        taco-multi-suitesparse-sddmm taco-multi-ttv taco-multi-blockspmm taco-multi-spadd

COPY . /mosaic-artifact
RUN test -f mosaic-benchmarks/run-figure.py && \
    mkdir -p /temp tensor_algebra_systems_src scripts/bench-scripts/figs && \
    find scripts/bench-scripts -name bench.sh -exec chmod +x {} + && \
    find scripts/bench-scripts -name bench.sh -execdir mkdir -p result \; && \
    find mosaic scripts tensor_algebra_systems_lib mosaic-benchmarks -type f \
        ! -path 'mosaic/build/*' ! -path 'tensor_algebra_systems_lib/tblis/*' -print0 | \
        sort -z | xargs -0 sha256sum > /opt/mosaic-build-info/sources.sha256 && \
    sha256sum Dockerfile .dockerignore docker.md >> /opt/mosaic-build-info/sources.sha256 && \
    dpkg-query -W -f='${Package}\t${Version}\n' > /opt/mosaic-build-info/packages.tsv && \
    printf 'base=%s\nsnapshot=%s\ncuda=%s\n' "$BASE_IMAGE" "$UBUNTU_SNAPSHOT" "$WITH_CUDA" \
        > /opt/mosaic-build-info/build.txt

RUN chmod +x scripts/docker-entrypoint.sh && \
    printf '\nsource /mosaic-artifact/scripts/mosaic_env_var.sh "${MOSAIC_LIBRARIES:-tblis,mkl}"\n' >> /root/.bashrc
WORKDIR /mosaic-artifact/scripts/bench-scripts
ENTRYPOINT ["/mosaic-artifact/scripts/docker-entrypoint.sh"]
CMD ["bash"]







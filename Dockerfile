FROM docker.io/ubuntu:22.04
LABEL description="mosaic-artifact"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
        build-essential software-properties-common && \
    add-apt-repository -y ppa:ubuntu-toolchain-r/test && \
    add-apt-repository -y ppa:zeehio/libxp && \
    dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y \
        wget \
	curl \
        git make gcc g++ \
        python3 python3-dev python3-pip python3-venv \
        graphviz \
        xxd \
        time \
        vim \
        cmake \
        texinfo\
        libtool-bin\
        bzip2 \
        && \
        pip install numpy scipy pandas matplotlib



# Switch shell to bash
SHELL ["/bin/bash", "--login", "-c"]

COPY . /mosaic-artifact

# Build the Mosaic Compiler
RUN mkdir /temp
WORKDIR /mosaic-artifact/mosaic
RUN mkdir -p build

# Set up a directory that will store all the external systems.
# To actually set up systems, use the scripts provided in 
# mosaic-artifact/scripts
WORKDIR /mosaic-artifact
RUN mkdir -p tensor_algebra_systems_src


WORKDIR /mosaic-artifact/scripts
RUN chmod 777 *
RUN echo "source /mosaic-artifact/scripts/mosaic_env_var.sh" >> /root/.bashrc

WORKDIR /mosaic-artifact/mosaic/build
RUN cmake -DCMAKE_BUILD_TYPE='Release'\
    -DCMAKE_INSTALL_PREFIX="${HOME}"  \
    -DBENCHMARK_DOWNLOAD_DEPENDENCIES=ON  ../ 
RUN make







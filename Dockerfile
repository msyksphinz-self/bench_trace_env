FROM ubuntu:24.04

# 環境変数設定（必要に応じて変更）
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

ARG RISCV_ARG=/riscv
ENV RISCV=${RISCV_ARG}

# 必要なパッケージをインストール
RUN apt-get update && apt-get install -y \
    build-essential \
    g++ \
    gcc \
    make \
    perl \
    python3 \
    time \
    wget \
    curl \
    unzip \
    vim \
    nano \
    less \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# RUN apt-get update && apt-get install -y \
#     gfortran \
#     && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y python3-tomli

# RUN apt-get update && apt-get install -y \
#     clang \
#     llvm \
#     lld \
#     libomp-dev \
#     && apt-get clean && rm -rf /var/lib/apt/lists/*


# RUN apt-get update && apt-get install -y \
#     qemu-system-misc \
#     qemu-user-static \
#     gcc-riscv64-linux-gnu \
#     g++-riscv64-linux-gnu \
#     gfortran-riscv64-linux-gnu \
#     && apt-get clean && rm -rf /var/lib/apt/lists/*
#
# RUN ln -s /usr/riscv64-linux-gnu/lib/ld-linux-riscv64-lp64d.so.1 /lib

RUN apt-get update && apt-get install -y \
    gfortran-riscv64-linux-gnu \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y \
    sqlite3 \
	gnuplot \
	libdb-dev \
	libboost-all-dev \
	build-essential \
	cmake \
	libboost-dev \
	libboost-serialization-dev \
	libboost-filesystem-dev \
	libboost-iostreams-dev \
	libboost-program-options-dev \
	zlib1g-dev \
	libquadmath0 \
	valgrind \
	ocaml \
	ocamlbuild \
	autoconf \
	automake \
	indent \
	libtool \
	fig2dev \
	libnum-ocaml-dev \
	libbz2-dev \
	libsqlite3-dev \
	python3-pip \
	ninja-build \
	libglib2.0-dev \
    texinfo \
    autotools-dev \
    bc \
    bison \
    curl \
    device-tree-compiler \
    flex \
    gawk \
    gperf \
    libexpat-dev \
    libgmp-dev \
    libmpc-dev \
    libmpfr-dev \
    libtool \
    libusb-1.0-0-dev \
    patchutils \
    pkg-config \
    texinfo \
    zlib1g-dev

RUN apt-get update && apt-get install -y cmake git

# # Start installing QEMU
# ENV QEMU_VERSION=10.1.0
# WORKDIR /tmp/
# RUN curl -L https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz | tar xJ && \
#     cd qemu-${QEMU_VERSION} && \
#     mkdir -p build && cd build && \
#     ../configure --target-list=riscv64-softmmu,riscv64-linux-user && \
#     make -j$(nproc) && \
#     make install

WORKDIR /tmp/

ENV RISCV=/riscv
RUN curl -L https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2025.10.28/riscv64-elf-ubuntu-24.04-gcc.tar.xz | tar xJ && \
    mv /tmp/riscv ${RISCV}

ENV RISCV=/riscv-linux
RUN curl -L https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2025.10.28/riscv64-glibc-ubuntu-24.04-gcc.tar.xz | tar xJ && \
    mv /tmp/riscv ${RISCV}

ENV PATH=$PATH:$RISCV/bin
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$RISCV/lib


RUN echo $RISCV

# RUN apt-get update && apt-get install -y libjemalloc-dev libjemalloc2

RUN apt-get update && apt-get install -y rsync
RUN apt-get update && apt-get install -y parallel
RUN apt-get update && apt-get install -y \
    p7zip-full \
    genisoimage \
    libpixman-1-dev \
    gzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y build-essential checkinstall libncursesw5-dev libssl-dev libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev
RUN wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tgz && \
    tar -xvf Python-2.7.18.tgz && \
    cd Python-2.7.18 && \
    ./configure --enable-optimizations && \
    make && make install && \
    cd - && rm -rf Python2.7.18*

RUN apt-get update && apt-get install libpython3-dev python3-dev

WORKDIR /workspace

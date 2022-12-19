FROM python:3.10-slim AS base

FROM base AS compile-image-base
ENV USE_CUDA=0
ENV USE_ROCM=0
ENV USE_NCCL=0
ENV USE_DISTRIBUTED=0
ENV USE_PYTORCH_QNNPACK=0
ENV MAX_JOBS=2

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    checkinstall \
    cmake \
    libopenblas-dev \
    git \
    build-essential \
    ffmpeg \
    libsm6 \
    libxext6 \
    wget \
    pkg-config \
    libbrotli-dev \
    libgif-dev \
    libjpeg-dev \
    libopenexr-dev \
    libpng-dev \
    libwebp-dev \
    libavif-dev \
    libopencv-dev \
    libgflags-dev \
    doxygen \
    clang && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
# Make sure we use the virtualenv:
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install astunparse numpy ninja pyyaml setuptools cmake cffi typing_extensions future six requests dataclasses scikit-build pyyaml meson sympy




# Seperate python build due to slow build times
FROM compile-image-base AS python-compile

WORKDIR /pytorch

RUN git clone --recursive https://github.com/pytorch/pytorch /pytorch && \
    git submodule sync && \
    git submodule update --init --recursive --jobs 0

RUN python setup.py install

RUN git clone https://github.com/pytorch/vision.git /torchvision

WORKDIR /torchvision

RUN python setup.py install




# Seperate deb compile base so run in parallel with python build due to slow python build speed
FROM compile-image-base AS deb-compile

# Install cjxl
RUN git clone --recursive https://github.com/libjxl/libjxl.git /libjxl

WORKDIR /libjxl

RUN git submodule update --init --recursive && mkdir -p /libjxl/build

ENV CC=clang CXX=clang++

WORKDIR /libjxl/build

RUN cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF .. && \
    cmake --build . -- -j$(nproc)

RUN checkinstall --install=yes --default -D --pkgname "cjxl" cmake --install . && \
    cp cjxl_*.deb /cjxl.deb

# Install cavif
RUN apt-get update && \
    apt-get install -y --no-install-recommends \ 
    nasm && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* 

RUN git clone --recurse-submodules --recursive https://github.com/link-u/cavif /cavif

WORKDIR /cavif

RUN bash scripts/apply-patches.sh && \
    bash scripts/build-deps.sh && \
    mkdir build

WORKDIR /cavif/build

ENV CC=gcc CXX=g++

RUN cmake -G 'Ninja' .. && \
    ninja -j$(nproc)

RUN checkinstall --install=yes --default -D --pkgname "cavif" ninja install && \
    cp cavif_*.deb /cavif.deb




# Actual deployment image
FROM base

ENV PATH="/opt/venv/bin:$PATH"

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ffmpeg \
    wget \
    libopenblas-dev \
    libgif-dev \
    libjpeg-dev \
    libopenexr-dev \
    libpng-dev \
    libwebp-dev \
    libavif-dev \
    sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=python-compile /opt/venv /opt/venv
COPY --from=deb-compile /cjxl.deb /tmp/cjxl.deb
COPY --from=deb-compile /cavif.deb /tmp/cavif.deb

RUN dpkg -i /tmp/cjxl.deb && rm -f /tmp/cjxl.deb
RUN dpkg -i /tmp/cavif.deb && rm -f /tmp/cavif.deb

WORKDIR /

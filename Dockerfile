FROM python:3.11-slim AS base

FROM base AS compile-image-base
ENV USE_CUDA=0
ENV USE_ROCM=0
ENV USE_NCCL=0
ENV USE_DISTRIBUTED=0
ENV USE_PYTORCH_QNNPACK=0
ENV MAX_JOBS=4

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




# Seperate torch build due to slow build times
FROM compile-image-base AS torch-compile

#WORKDIR /pytorch

#RUN git clone --recursive https://github.com/pytorch/pytorch /pytorch && \
#    git submodule sync && \
#    git submodule update --init --recursive --jobs $(nproc)

#RUN python setup.py install

#RUN git clone https://github.com/pytorch/vision.git /torchvision

#WORKDIR /torchvision

#RUN python setup.py install

# Curl https://raw.githubusercontent.com/pytorch/pytorch/main/requirements.txt and install it
RUN curl https://raw.githubusercontent.com/pytorch/pytorch/main/requirements.txt --output requirements.txt && \
    pip install -r requirements.txt && \
    pip install pillow
RUN pip install --pre torch torchvision --index-url https://download.pytorch.org/whl/nightly/cpu



# Build cjxl
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




# Build cavif
FROM rust:latest AS rust-compile

RUN apt-get update && \
    apt-get install -y --no-install-recommends \ 
    nasm && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* 

RUN git clone --recurse-submodules --recursive https://github.com/kornelski/cavif-rs.git /cavif

WORKDIR /cavif

RUN cargo build --release && \
    cp target/release/cavif /usr/local/bin/cavif





# Actual deployment image
FROM base

ENV PATH="/opt/venv/bin:$PATH"
ENV LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ffmpeg \
    wget \
    sudo \
    build-essential \
    pkg-config \
    imagemagick \
    exiftool \
    libopenblas-dev \
    libgif-dev \
    libjpeg-dev \
    libopenexr-dev \
    libpng-dev \
    libwebp-dev \
    libavif-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=torch-compile /opt/venv /opt/venv
COPY --from=deb-compile /cjxl.deb /tmp/cjxl.deb
COPY --from=rust-compile /usr/local/bin/cavif /usr/local/bin/cavif

RUN dpkg -i /tmp/cjxl.deb && rm -f /tmp/cjxl.deb

WORKDIR /

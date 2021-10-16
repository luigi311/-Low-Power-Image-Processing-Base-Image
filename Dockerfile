FROM python:3.8-slim AS compile-image
ENV USE_CUDA=0
ENV USE_ROCM=0
ENV USE_NCCL=0
ENV USE_DISTRIBUTED=0
ENV USE_PYTORCH_QNNPACK=0
ENV MAX_JOBS=8

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
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
    doxygen \
    clang && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
# Make sure we use the virtualenv:
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install astunparse numpy ninja pyyaml setuptools cmake cffi typing_extensions future six requests dataclasses scikit-build pyyaml

WORKDIR /pytorch

RUN git clone --recursive https://github.com/pytorch/pytorch /pytorch && \
    git submodule sync && \
    git submodule update --init --recursive --jobs 0

RUN python setup.py install

RUN git clone https://github.com/pytorch/vision.git /torchvision

WORKDIR /torchvision

RUN python setup.py install

# Install cjxl
RUN git clone https://github.com/libjxl/libjxl.git /libjxl --recursive

WORKDIR /libjxl

RUN git submodule update --init --recursive && mkdir -p /libjxl/build

ENV CC=clang CXX=clang++

WORKDIR /libjxl/build

RUN cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF .. && \
    cmake --build . -- -j$(nproc) && \
    cmake --install .








FROM python:3.8-slim

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

COPY --from=compile-image /opt/venv /opt/venv
COPY --from=compile-image /libjxl/build /libjxl/build
COPY --from=compile-image /libjxl/third_party /libjxl/third_party
COPY --from=compile-image /libjxl/lib/include /libjxl/lib/include

WORKDIR /libjxl/build

RUN cmake --install .

WORKDIR /

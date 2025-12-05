# Vehicle Edge Platform - Development Container
# Ubuntu 24.04 with all build dependencies

FROM ubuntu:24.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install system packages
RUN apt-get update && apt-get install -y \
    # Build tools
    build-essential \
    cmake \
    git \
    pkg-config \
    wget \
    curl \
    ca-certificates \
    sudo \
    \
    # Logging and testing
    libgoogle-glog-dev \
    libgflags-dev \
    libgtest-dev \
    libgmock-dev \
    \
    # Core libraries
    liblua5.4-dev \
    libyaml-cpp-dev \
    nlohmann-json3-dev \
    \
    # gRPC and Protobuf
    libgrpc++-dev \
    libprotobuf-dev \
    protobuf-compiler \
    protobuf-compiler-grpc \
    libabsl-dev \
    \
    # DDS
    cyclonedds-dev \
    cyclonedds-tools \
    \
    # MQTT and compression
    libmosquitto-dev \
    libzstd-dev \
    \
    # CAN utilities
    can-utils \
    \
    # Development tools
    gdb \
    valgrind \
    clang-format \
    tmux \
    && rm -rf /var/lib/apt/lists/*

# Install concurrentqueue (header-only, not in Ubuntu repos)
RUN cd /tmp && \
    git clone --depth 1 https://github.com/cameron314/concurrentqueue.git && \
    cd concurrentqueue && \
    mkdir -p build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          .. && \
    cmake --install . && \
    rm -rf /tmp/concurrentqueue

# Install dbcppp (DBC file parser)
RUN cd /tmp && \
    git clone --depth 1 https://github.com/xR3b0rn/dbcppp.git && \
    cd dbcppp && \
    mkdir -p build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release \
          -Dbuild_kcd=OFF \
          -Dbuild_tools=OFF \
          -Dbuild_tests=OFF \
          -Dbuild_examples=OFF \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    rm -rf /tmp/dbcppp

# Install Open1722 (IEEE 1722 AVTP library)
RUN cd /tmp && \
    git clone --depth 1 https://github.com/COVESA/Open1722.git && \
    cd Open1722 && \
    mkdir -p build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    rm -rf /tmp/Open1722

# Create non-root user (handle existing GID/UID)
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN if ! getent group $USER_GID >/dev/null; then groupadd --gid $USER_GID $USERNAME; fi \
    && if ! getent passwd $USER_UID >/dev/null; then useradd --uid $USER_UID --gid $USER_GID -m $USERNAME; \
       else usermod -l $USERNAME -d /home/$USERNAME -m $(getent passwd $USER_UID | cut -d: -f1) 2>/dev/null || true; fi \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Set working directory
WORKDIR /workspaces/vehicle-edge-platform

# Default to non-root user
USER $USERNAME

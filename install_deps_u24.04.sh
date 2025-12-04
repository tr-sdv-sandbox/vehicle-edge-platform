#!/bin/bash
# Vehicle Edge Platform - Install Third-Party Dependencies (Ubuntu 24.04)
# Run this once on a fresh Ubuntu 24.04 system

set -e

echo "=== Vehicle Edge Platform - Installing Dependencies (Ubuntu 24.04) ==="
echo ""

# Check if running as root for apt operations
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# ==============================================================================
# System packages (apt)
# ==============================================================================
echo "=== Installing system packages ==="

$SUDO apt-get update
$SUDO apt-get install -y \
    build-essential \
    cmake \
    git \
    pkg-config \
    \
    libgoogle-glog-dev \
    libgflags-dev \
    libgtest-dev \
    libgmock-dev \
    \
    liblua5.4-dev \
    libyaml-cpp-dev \
    nlohmann-json3-dev \
    \
    libgrpc++-dev \
    libprotobuf-dev \
    protobuf-compiler \
    protobuf-compiler-grpc \
    libabsl-dev \
    \
    libmosquitto-dev \
    libzstd-dev \
    \
    cyclonedds-dev \
    cyclonedds-tools \
    \
    can-utils

echo ""

# ==============================================================================
# concurrentqueue (lock-free queue for libvssdag)
# ==============================================================================
echo "=== Installing concurrentqueue ==="

if [ -f /usr/local/include/concurrentqueue/concurrentqueue.h ]; then
    echo "concurrentqueue already installed, skipping"
else
    cd /tmp
    rm -rf concurrentqueue
    git clone --depth 1 https://github.com/cameron314/concurrentqueue.git
    cd concurrentqueue
    mkdir -p build && cd build
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          ..
    $SUDO cmake --install .
    echo "concurrentqueue installed"
fi

echo ""

# ==============================================================================
# dbcppp (DBC file parser for libvssdag)
# ==============================================================================
echo "=== Installing dbcppp ==="

if [ -f /usr/local/lib/libdbcppp.so ] || [ -f /usr/local/lib/libdbcppp.a ]; then
    echo "dbcppp already installed, skipping"
else
    cd /tmp
    rm -rf dbcppp
    git clone --depth 1 https://github.com/xR3b0rn/dbcppp.git
    cd dbcppp
    mkdir -p build && cd build
    cmake -DCMAKE_BUILD_TYPE=Release \
          -Dbuild_kcd=OFF \
          -Dbuild_tools=OFF \
          -Dbuild_tests=OFF \
          -Dbuild_examples=OFF \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          ..
    make -j$(nproc)
    $SUDO make install
    $SUDO ldconfig
    echo "dbcppp installed"
fi

echo ""

# ==============================================================================
# Summary
# ==============================================================================
echo "=== Installation Complete ==="
echo ""
echo "Installed dependencies:"
echo "  - Build tools (cmake, g++, etc.)"
echo "  - Google libraries (glog, gflags, gtest)"
echo "  - Lua 5.4"
echo "  - YAML-CPP, nlohmann-json"
echo "  - gRPC + Protobuf"
echo "  - Mosquitto (MQTT)"
echo "  - Zstd (compression)"
echo "  - CycloneDDS"
echo "  - CAN utilities"
echo "  - concurrentqueue"
echo "  - dbcppp"
echo ""
echo "Next steps:"
echo "  1. Run ./setup.sh to clone component repositories"
echo "  2. Run ./build-all.sh to build everything"
echo ""

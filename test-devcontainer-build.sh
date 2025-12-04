#!/bin/bash
# Test the devcontainer build without VS Code
#
# Usage:
#   ./test-devcontainer-build.sh          # Build and run tests
#   ./test-devcontainer-build.sh --shell  # Open interactive shell

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Build the devcontainer image if needed
if ! docker image inspect vep-dev >/dev/null 2>&1; then
    echo "=== Building devcontainer image ==="
    docker build --network=host -t vep-dev .devcontainer/
fi

if [[ "$1" == "--shell" ]]; then
    echo "=== Opening interactive shell ==="
    docker run -it --rm \
        -v "$(pwd):/workspaces/vehicle-edge-platform" \
        -w /workspaces/vehicle-edge-platform \
        vep-dev \
        bash
else
    echo "=== Running setup and build ==="
    docker run --rm \
        -v "$(pwd):/workspaces/vehicle-edge-platform" \
        -w /workspaces/vehicle-edge-platform \
        vep-dev \
        bash -c './setup.sh --https && \
            rm -rf build-docker && \
            mkdir -p build-docker && \
            cd build-docker && \
            cmake .. -DCMAKE_BUILD_TYPE=Release -DVEP_BUILD_TESTS=ON && \
            cmake --build . -j$(nproc)'
fi

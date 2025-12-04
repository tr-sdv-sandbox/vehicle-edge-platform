#!/bin/bash
# Test the devcontainer build without VS Code
#
# Usage (from host):
#   ./test-devcontainer-build.sh              # Build project in container
#   ./test-devcontainer-build.sh --shell      # Open interactive shell
#   ./test-devcontainer-build.sh --rebuild    # Rebuild container image first
#
# Usage (inside container):
#   ./test-devcontainer-build.sh              # Build project directly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if we're already inside a container (no docker available)
if ! command -v docker >/dev/null 2>&1; then
    echo "=== Building inside container ==="
    ./setup.sh --https || true
    rm -rf build-docker
    mkdir -p build-docker
    cd build-docker
    cmake .. -DCMAKE_BUILD_TYPE=Release -DVEP_BUILD_TESTS=ON
    cmake --build . -j$(nproc)
    exit 0
fi

# Parse arguments
REBUILD=false
SHELL_MODE=false
for arg in "$@"; do
    case $arg in
        --rebuild) REBUILD=true ;;
        --shell) SHELL_MODE=true ;;
    esac
done

# Build the devcontainer image if needed or if --rebuild specified
if $REBUILD || ! docker image inspect vep-dev >/dev/null 2>&1; then
    echo "=== Building devcontainer image ==="
    docker build --network=host -t vep-dev .devcontainer/
fi

if $SHELL_MODE; then
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

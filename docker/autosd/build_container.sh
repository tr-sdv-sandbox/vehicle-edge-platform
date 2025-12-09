#!/bin/bash
# Build the AutoSD development container
# Usage: ./build.sh [--no-cache]

set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

BUILD_ARGS="--network host"

if [[ "$1" == "--no-cache" ]]; then
    BUILD_ARGS="$BUILD_ARGS --no-cache"
    echo "Building without cache..."
fi

echo "=== Building AutoSD Development Container ==="
echo ""

docker build $BUILD_ARGS -t autosd-vep -f Dockerfile.autosd .

echo ""
echo "=== Build Complete ==="
echo "Run with: docker run -it --privileged --network host -v \$(pwd):/workspace autosd-vep"

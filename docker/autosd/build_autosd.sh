#!/bin/bash
# Vehicle Edge Platform - Build for AutoSD
# Builds the project inside the AutoSD container
#
# Usage: ./build_autosd.sh [Release|Debug] [jobs] [--strip] [--no-cache]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_TYPE="Release"
JOBS="$(nproc)"
STRIP_BINARIES=false
BUILD_CONTAINER=false
OUTPUT_DIR="$PROJECT_ROOT/build-autosd"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --strip)
            STRIP_BINARIES=true
            shift
            ;;
        --rebuild-container|--no-cache)
            BUILD_CONTAINER=true
            shift
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        Debug|Release)
            BUILD_TYPE="$1"
            shift
            ;;
        [0-9]*)
            JOBS="$1"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [Release|Debug] [jobs] [--strip] [--rebuild-container] [--output DIR]"
            echo ""
            echo "Options:"
            echo "  Release|Debug       Build type (default: Release)"
            echo "  jobs                Number of parallel jobs (default: nproc)"
            echo "  --strip             Strip debug symbols from binaries (Release only)"
            echo "  --rebuild-container Rebuild the Docker container before building"
            echo "  --output DIR        Output directory (default: build-autosd)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

IMAGE_NAME="autosd-vep"

echo "=== Building Vehicle Edge Platform for AutoSD ==="
echo "Build type: $BUILD_TYPE"
echo "Parallel jobs: $JOBS"
echo "Output directory: $OUTPUT_DIR"
if [ "$STRIP_BINARIES" = true ] && [ "$BUILD_TYPE" = "Release" ]; then
    echo "Strip binaries: yes"
fi
echo ""

# Check if container image exists or needs rebuild
if [ "$BUILD_CONTAINER" = true ] || ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    echo "=== Building AutoSD container ==="
    "$SCRIPT_DIR/build_container.sh"
    echo ""
fi

# Check if components exist
if [ ! -d "$PROJECT_ROOT/components/libvss-types" ]; then
    echo "ERROR: Components not found. Run ./setup.sh first."
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Build command to run inside container
STRIP_FLAG=""
if [ "$STRIP_BINARIES" = true ]; then
    STRIP_FLAG="--strip"
fi

# Run build inside container
# Mount project as /workspace, build to /workspace/build-autosd
# Run as current user to avoid permission issues with created files
echo "=== Running build in AutoSD container ==="
docker run --rm \
    --network host \
    --user "$(id -u):$(id -g)" \
    -v "$PROJECT_ROOT:/workspace:rw" \
    -w /workspace \
    -e BUILD_TYPE="$BUILD_TYPE" \
    -e JOBS="$JOBS" \
    -e STRIP_FLAG="$STRIP_FLAG" \
    -e HOME="/tmp" \
    "$IMAGE_NAME" \
    /bin/bash -c '
        set -e

        BUILD_DIR="/workspace/build-autosd"

        echo "Configuring with CMake..."
        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        cmake /workspace \
            -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
            -DVEP_BUILD_TESTS=ON \
            -DVEP_BUILD_EXAMPLES=ON

        echo ""
        echo "Building with $JOBS parallel jobs..."
        cmake --build . -j"$JOBS"

        # Strip binaries if requested (Release only)
        if [ -n "$STRIP_FLAG" ] && [ "$BUILD_TYPE" = "Release" ]; then
            echo ""
            echo "Stripping debug symbols..."
            find "$BUILD_DIR" -type f -executable ! -name "*.sh" -exec file {} \; | \
                grep -E "ELF.*executable|ELF.*shared object" | cut -d: -f1 | \
                xargs -r strip --strip-unneeded 2>/dev/null || true
            echo "Done."
        fi
    '

echo ""
echo "=== AutoSD Build Complete ==="
echo ""
echo "Binaries are in: $OUTPUT_DIR"
echo ""
echo "Key executables:"
echo "  $OUTPUT_DIR/vep-core/vep_exporter"
echo "  $OUTPUT_DIR/vep-core/vep_mqtt_receiver"
echo "  $OUTPUT_DIR/vep-core/probes/vep_can_probe/vep_can_probe"
echo "  $OUTPUT_DIR/vep-core/probes/vep_otel_probe/vep_otel_probe"
echo ""
echo "These binaries are built for CentOS Stream 9 / AutoSD."

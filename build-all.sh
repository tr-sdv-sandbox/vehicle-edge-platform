#!/bin/bash
# Vehicle Edge Platform - Build All Components
# Uses top-level CMakeLists.txt to build everything

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
BUILD_TYPE="${1:-Release}"
JOBS="${2:-$(nproc)}"

echo "=== Building Vehicle Edge Platform ==="
echo "Build type: $BUILD_TYPE"
echo "Parallel jobs: $JOBS"
echo ""

# Check if components exist
if [ ! -d "$SCRIPT_DIR/components/libvss-types" ]; then
    echo "ERROR: Components not found. Run ./setup.sh first."
    exit 1
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake "$SCRIPT_DIR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DVEP_BUILD_TESTS=ON \
    -DVEP_BUILD_EXAMPLES=ON

cmake --build . -j"$JOBS"

echo ""
echo "=== Build Complete ==="
echo ""
echo "Binaries are in: $BUILD_DIR"
echo ""
echo "Key executables:"
echo "  $BUILD_DIR/vep-core/vep_exporter"
echo "  $BUILD_DIR/vep-core/vep_mqtt_receiver"
echo "  $BUILD_DIR/vep-core/probes/vep_can_probe/vep_can_probe"
echo "  $BUILD_DIR/vep-core/probes/vep_otel_probe/vep_otel_probe"
echo ""

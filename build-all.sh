#!/bin/bash
# Vehicle Edge Platform - Build All Components
# Uses top-level CMakeLists.txt to build everything

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
BUILD_TYPE="Release"
JOBS="$(nproc)"
STRIP_BINARIES=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --strip)
            STRIP_BINARIES=true
            shift
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
            echo "Usage: $0 [Release|Debug] [jobs] [--strip]"
            echo ""
            echo "Options:"
            echo "  Release|Debug  Build type (default: Release)"
            echo "  jobs           Number of parallel jobs (default: nproc)"
            echo "  --strip        Strip debug symbols from binaries (Release only)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=== Building Vehicle Edge Platform ==="
echo "Build type: $BUILD_TYPE"
echo "Parallel jobs: $JOBS"
if [ "$STRIP_BINARIES" = true ] && [ "$BUILD_TYPE" = "Release" ]; then
    echo "Strip binaries: yes"
fi
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

# Strip binaries if requested (Release only)
if [ "$STRIP_BINARIES" = true ] && [ "$BUILD_TYPE" = "Release" ]; then
    echo ""
    echo "Stripping debug symbols..."
    find "$BUILD_DIR" -type f -executable ! -name "*.sh" -exec file {} \; | \
        grep -E "ELF.*executable|ELF.*shared object" | cut -d: -f1 | \
        xargs -r strip --strip-unneeded 2>/dev/null || true
    echo "Done."
fi

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

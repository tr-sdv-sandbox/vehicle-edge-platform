#!/bin/bash
# Vehicle Edge Platform - Build UBI Minimal Runtime Container for AutoSD
# Creates a minimal runtime container using Red Hat UBI minimal base
#
# Usage: ./build_runtime_ubi.sh [--no-cache] [--tag TAG] [--slim]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE_TAG="vep-autosd-runtime:ubi"
BUILD_IMAGE="autosd-vep"
NO_CACHE=""
SLIM=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --slim)
            SLIM=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--no-cache] [--tag TAG] [--slim]"
            echo ""
            echo "Options:"
            echo "  --no-cache    Don't use Docker cache"
            echo "  --tag TAG     Tag for runtime image (default: vep-autosd-runtime:ubi)"
            echo "  --slim        Flatten image to reduce size"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=== Building VEP UBI Minimal Runtime Container ==="
echo "Build image: $BUILD_IMAGE"
echo "Runtime tag: $IMAGE_TAG"
echo ""

# Check if build container exists
if ! docker image inspect "$BUILD_IMAGE" > /dev/null 2>&1; then
    echo "Build container '$BUILD_IMAGE' not found."
    echo "Building it first..."
    "$SCRIPT_DIR/build_container.sh"
    echo ""
fi

# Build runtime container
echo "=== Building UBI minimal runtime container ==="
docker build \
    --network host \
    $NO_CACHE \
    -t "$IMAGE_TAG" \
    -f "$SCRIPT_DIR/Dockerfile.runtime.ubi" \
    "$PROJECT_ROOT"

echo ""

# Flatten image if --slim requested
if [ "$SLIM" = true ]; then
    echo "=== Flattening image for smaller size ==="
    CONTAINER_ID=$(docker create "$IMAGE_TAG")
    docker export "$CONTAINER_ID" | docker import - "${IMAGE_TAG}-slim"
    docker rm "$CONTAINER_ID" > /dev/null
    # Retag slim as the main tag
    docker tag "${IMAGE_TAG}-slim" "$IMAGE_TAG"
    docker rmi "${IMAGE_TAG}-slim" > /dev/null 2>&1 || true
    echo "Image flattened."
fi

echo ""
echo "=== UBI Minimal Runtime Container Built Successfully ==="
echo ""

# Show image sizes
echo "Image sizes:"
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -E "^(REPOSITORY|$BUILD_IMAGE|vep-autosd)"
echo ""

echo "Run with:"
echo "  docker run -it --privileged --network host $IMAGE_TAG"
echo ""
echo "Available binaries:"
echo "  vep_can_probe      - CAN -> VSS -> DDS"
echo "  vep_otel_probe     - OTLP gRPC -> DDS"
echo "  vep_exporter       - DDS -> compressed MQTT"
echo "  vep_mqtt_receiver  - MQTT receiver/decoder"
echo "  kuksa_dds_bridge   - KUKSA <-> DDS bridge"
echo "  rt_dds_bridge      - DDS <-> RT transport"
echo "  vep_host_metrics   - Host metrics collector"
echo ""
echo "Note: UBI minimal does not include mosquitto or can-utils."
echo "      Use for production deployments where these are provided externally."

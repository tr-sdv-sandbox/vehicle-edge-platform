#!/bin/bash
# Vehicle Edge Platform - Cross-compilation Build Script
# Builds ARM64 containers using QEMU emulation
#
# Usage: ./build_cross.sh [--platform PLATFORM] [--runtime] [--ubi] [--slim] [--no-cache]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Defaults
PLATFORM="linux/arm64"
BUILD_RUNTIME=false
BUILD_UBI=false
SLIM=false
NO_CACHE=""
BUILDER_NAME="vep-cross-builder"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --runtime)
            BUILD_RUNTIME=true
            shift
            ;;
        --ubi)
            BUILD_UBI=true
            BUILD_RUNTIME=true
            shift
            ;;
        --slim)
            SLIM=true
            shift
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Cross-compile VEP for ARM64 (or other platforms) using QEMU emulation."
            echo ""
            echo "Options:"
            echo "  --platform PLATFORM  Target platform (default: linux/arm64)"
            echo "  --runtime            Build runtime container (not just build container)"
            echo "  --ubi                Build UBI minimal runtime (implies --runtime)"
            echo "  --slim               Flatten runtime image for smaller size"
            echo "  --no-cache           Don't use Docker cache"
            echo ""
            echo "Examples:"
            echo "  $0                           # Build ARM64 build container"
            echo "  $0 --runtime --slim          # Build ARM64 runtime container"
            echo "  $0 --ubi --slim              # Build ARM64 UBI minimal runtime"
            echo "  $0 --platform linux/arm/v7   # Build ARMv7 (32-bit)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Extract arch suffix for tags (e.g., linux/arm64 -> arm64)
ARCH_SUFFIX=$(echo "$PLATFORM" | sed 's|linux/||' | sed 's|/|-|g')

echo "=== VEP Cross-Compilation Build ==="
echo "Platform: $PLATFORM"
echo "Arch suffix: $ARCH_SUFFIX"
echo ""

# Step 1: Check/setup QEMU
echo "=== Step 1: Checking QEMU setup ==="

# First, ensure QEMU emulators are registered (needed for cross-platform builds)
echo "Ensuring QEMU emulators are registered..."
docker run --rm --privileged tonistiigi/binfmt --install all > /dev/null 2>&1 || true

# Verify Docker works
if ! docker run --rm alpine:latest uname -m > /dev/null 2>&1; then
    echo "ERROR: Docker not working. Trying with verbose output:"
    docker run --rm alpine:latest uname -m
    exit 1
fi

# Verify QEMU works for target platform
echo -n "Verifying $PLATFORM emulation... "
if docker run --rm --platform "$PLATFORM" alpine:latest uname -m > /dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    echo ""
    echo "ERROR: Cannot run $PLATFORM containers."
    echo "Please run manually and retry:"
    echo "  sudo docker run --rm --privileged tonistiigi/binfmt --install all"
    exit 1
fi
echo ""

# Step 2: Setup buildx builder with Docker socket access
echo "=== Step 2: Setting up buildx builder ==="
if ! docker buildx inspect "$BUILDER_NAME" > /dev/null 2>&1; then
    echo "Creating buildx builder: $BUILDER_NAME (with Docker socket access)"
    # Mount Docker socket so buildx can see local images
    docker buildx create --name "$BUILDER_NAME" \
        --driver docker-container \
        --driver-opt network=host \
        --driver-opt "image=moby/buildkit:buildx-stable-1" \
        --buildkitd-flags '--allow-insecure-entitlement network.host' \
        --config /dev/stdin <<EOF
[registry."docker.io"]
  mirrors = ["localhost:5000"]
EOF
    docker buildx use "$BUILDER_NAME"
    docker buildx inspect --bootstrap
else
    echo "Using existing builder: $BUILDER_NAME"
    docker buildx use "$BUILDER_NAME"
fi
echo ""

# Step 3: Build the build container
BUILD_TAG="autosd-vep:$ARCH_SUFFIX"
echo "=== Step 3: Building build container ==="
echo "Tag: $BUILD_TAG"
echo "This will take a while under QEMU emulation..."
echo ""

docker buildx build \
    --platform "$PLATFORM" \
    --network host \
    $NO_CACHE \
    -t "$BUILD_TAG" \
    -f "$SCRIPT_DIR/Dockerfile.autosd" \
    --load \
    "$PROJECT_ROOT"

echo ""
echo "Build container created: $BUILD_TAG"

# Step 4: Build runtime if requested
if [ "$BUILD_RUNTIME" = true ]; then
    if [ "$BUILD_UBI" = true ]; then
        RUNTIME_TAG="vep-autosd-runtime:ubi-$ARCH_SUFFIX"
        DOCKERFILE="Dockerfile.runtime.ubi"
    else
        RUNTIME_TAG="vep-autosd-runtime:$ARCH_SUFFIX"
        DOCKERFILE="Dockerfile.runtime"
    fi

    echo ""
    echo "=== Step 4: Building runtime container ==="
    echo "Tag: $RUNTIME_TAG"
    echo "Dockerfile: $DOCKERFILE"
    echo ""

    # For cross-platform builds, buildx can't access local images directly.
    # Solution: Start a temporary local registry, push the build image, then build.

    REGISTRY_PORT=5555
    REGISTRY_NAME="vep-temp-registry"
    LOCAL_BUILD_TAG="localhost:$REGISTRY_PORT/$BUILD_TAG"

    echo "Starting temporary local registry..."
    docker rm -f "$REGISTRY_NAME" 2>/dev/null || true
    docker run -d --name "$REGISTRY_NAME" -p $REGISTRY_PORT:5000 registry:2

    # Wait for registry to be ready
    sleep 2

    echo "Pushing $BUILD_TAG to local registry..."
    docker tag "$BUILD_TAG" "$LOCAL_BUILD_TAG"
    docker push "$LOCAL_BUILD_TAG"

    # Create a temporary Dockerfile with the registry-based FROM
    TEMP_DOCKERFILE=$(mktemp)
    sed "s|FROM autosd-vep AS builder|FROM $LOCAL_BUILD_TAG AS builder|" \
        "$SCRIPT_DIR/$DOCKERFILE" > "$TEMP_DOCKERFILE"

    echo "Building runtime container..."

    # Build runtime using buildx - now it can pull from local registry
    # Always use --no-cache-filter=builder to pick up source code changes
    # (the builder stage has COPY . . which must not be cached)
    docker buildx build \
        --platform "$PLATFORM" \
        --network host \
        --builder "$BUILDER_NAME" \
        --allow network.host \
        --no-cache-filter=builder \
        $NO_CACHE \
        -t "$RUNTIME_TAG" \
        -f "$TEMP_DOCKERFILE" \
        --load \
        "$PROJECT_ROOT"

    # Cleanup
    rm -f "$TEMP_DOCKERFILE"
    docker rm -f "$REGISTRY_NAME" 2>/dev/null || true
    docker rmi "$LOCAL_BUILD_TAG" 2>/dev/null || true

    # Flatten if --slim requested
    if [ "$SLIM" = true ]; then
        echo ""
        echo "=== Flattening image for smaller size ==="
        CONTAINER_ID=$(docker create --platform "$PLATFORM" "$RUNTIME_TAG")
        docker export "$CONTAINER_ID" | docker import --platform "$PLATFORM" - "${RUNTIME_TAG}-slim"
        docker rm "$CONTAINER_ID" > /dev/null
        docker tag "${RUNTIME_TAG}-slim" "$RUNTIME_TAG"
        docker rmi "${RUNTIME_TAG}-slim" > /dev/null 2>&1 || true
        echo "Image flattened."
    fi

    echo ""
    echo "Runtime container created: $RUNTIME_TAG"
fi

echo ""
echo "=== Cross-Compilation Complete ==="
echo ""

# Show created images
echo "Created images:"
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -E "^(REPOSITORY|.*$ARCH_SUFFIX)"
echo ""

# Verify architecture
echo "Verifying architecture:"
if [ "$BUILD_RUNTIME" = true ]; then
    VERIFY_TAG="$RUNTIME_TAG"
else
    VERIFY_TAG="$BUILD_TAG"
fi
echo -n "$VERIFY_TAG: "
docker run --rm --platform "$PLATFORM" "$VERIFY_TAG" uname -m
echo ""

echo "To test binaries:"
if [ "$BUILD_RUNTIME" = true ]; then
    echo "  docker run --rm --platform $PLATFORM $RUNTIME_TAG vep_can_probe --help"
else
    echo "  docker run --rm --platform $PLATFORM $BUILD_TAG uname -m"
fi

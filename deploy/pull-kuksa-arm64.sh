#!/bin/bash
# pull-kuksa-arm64.sh - Pull ARM64 KUKSA databroker image and save to tar
#
# This script pulls the ARM64 KUKSA databroker image from GitHub Container
# Registry and saves it to a tar file for transfer to air-gapped targets.
#
# Usage:
#   ./pull-kuksa-arm64.sh [OUTPUT_DIR]
#
# Examples:
#   ./pull-kuksa-arm64.sh                    # Saves to current directory
#   ./pull-kuksa-arm64.sh /tmp               # Saves to /tmp
#   ./pull-kuksa-arm64.sh ~/images           # Saves to ~/images
#
# Output:
#   kuksa-databroker-arm64.tar - Docker image tar file
#
# On target, load with:
#   podman load -i kuksa-databroker-arm64.tar

set -e

# Configuration
IMAGE_NAME="ghcr.io/eclipse-kuksa/kuksa-databroker"
IMAGE_TAG="0.6.0"
FULL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"
PLATFORM="linux/arm64"

# Parse arguments
OUTPUT_DIR="${1:-.}"
TAR_FILE="$OUTPUT_DIR/kuksa-databroker-arm64.tar"

echo "============================================================"
echo "Pull KUKSA Databroker ARM64 Image"
echo "============================================================"
echo ""
echo "Configuration:"
echo "  Image:       $FULL_IMAGE"
echo "  Platform:    $PLATFORM"
echo "  Output:      $TAR_FILE"
echo ""

# Create output directory if needed
mkdir -p "$OUTPUT_DIR"

# Step 1: Pull ARM64 image
echo "[1/2] Pulling ARM64 image..."
docker pull --platform "$PLATFORM" "$FULL_IMAGE"
echo "  Done"
echo ""

# Step 2: Save to tar
echo "[2/2] Saving image to tar file..."
docker save "$FULL_IMAGE" -o "$TAR_FILE"
TAR_SIZE=$(du -h "$TAR_FILE" | cut -f1)
echo "  Saved: $TAR_FILE ($TAR_SIZE)"
echo ""

echo "============================================================"
echo "Done! Transfer and load on target:"
echo ""
echo "  scp $TAR_FILE user@target:/tmp/"
echo "  ssh user@target 'podman load -i /tmp/$(basename $TAR_FILE)'"
echo ""
echo "Run KUKSA databroker on target:"
echo "  podman run -d --network host $FULL_IMAGE --insecure"
echo "============================================================"

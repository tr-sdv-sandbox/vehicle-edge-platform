#!/bin/bash
# kuksa-logger.sh - Display KUKSA databroker values using containerized logger
#
# Subscribes to all VSS signals in the KUKSA databroker and displays
# their values as they change.
#
# Usage:
#   ./kuksa-logger.sh [KUKSA_ADDRESS]
#   TARGET=1 ./kuksa-logger.sh [KUKSA_ADDRESS]
#
# Arguments:
#   KUKSA_ADDRESS    KUKSA databroker address (default: localhost:55555)
#
# Examples:
#   ./kuksa-logger.sh                          # Connect to localhost:55555
#   ./kuksa-logger.sh localhost:61234          # Connect to custom port
#   TARGET=1 ./kuksa-logger.sh 192.168.1.10:55555  # ARM64 target mode
#
# Prerequisites:
#   Dev mode:    docker image available (vep-autosd-runtime:ubi)
#   Target mode: podman image pre-loaded (vep-autosd-runtime:ubi-arm64)
#
# Note: The runtime container must include kuksa_logger (rebuild if missing)

set -e

# =============================================================================
# Configuration
# =============================================================================

TARGET="${TARGET:-}"

if [ -n "$TARGET" ]; then
    VEP_IMAGE="docker.io/library/vep-autosd-runtime:ubi-arm64"
    CONTAINER_PLATFORM="--arch arm64"
else
    VEP_IMAGE="vep-autosd-runtime:ubi"
    CONTAINER_PLATFORM=""
fi

# KUKSA address (can be overridden by first argument)
KUKSA_ADDRESS="${1:-localhost:55555}"

# =============================================================================
# Main
# =============================================================================

MODE_DESC="Dev (x86_64)"
[ -n "$TARGET" ] && MODE_DESC="Target (ARM64)"

echo "============================================================"
echo "KUKSA Logger"
echo "============================================================"
echo ""
echo "Configuration:"
echo "  Mode:           $MODE_DESC"
echo "  VEP Image:      $VEP_IMAGE"
echo "  KUKSA Address:  $KUKSA_ADDRESS"
echo ""

# Sync image from docker to podman (dev mode only)
if [ -z "$TARGET" ]; then
    echo "Syncing image from docker to podman..."
    docker save "$VEP_IMAGE" | podman load 2>/dev/null
    echo ""
fi

echo "Subscribing to KUKSA signals..."
echo "Press Ctrl+C to stop."
echo "============================================================"
echo ""

# Run kuksa_logger in container
podman run --rm -it \
    $CONTAINER_PLATFORM \
    --network host \
    "$VEP_IMAGE" \
    kuksa_logger \
        --address "$KUKSA_ADDRESS"

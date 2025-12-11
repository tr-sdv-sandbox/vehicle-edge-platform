#!/bin/bash
# avtp-canplayer.sh - Replay CAN data over IEEE 1722 AVTP using container
#
# Containerized version of run_avtp_canplayer.sh for deployment on targets.
#
# IMPORTANT: This script requires root/sudo to create AF_PACKET raw sockets for AVTP.
#   Rootless podman cannot grant CAP_NET_RAW to containers.
#
# Usage:
#   sudo ./avtp-canplayer.sh <interface> <logfile> [options]
#   sudo TARGET=1 ./avtp-canplayer.sh <interface> <logfile> [options]
#
# Arguments:
#   interface    Ethernet interface for AVTP (e.g., eth0, avtp0)
#   logfile      Path to candump log file
#
# Options (passed to avtp_canplayer):
#   --speed N         Playback speed multiplier (default: 1.0)
#   --loop            Loop continuously
#   --no-timestamps   Ignore timestamps, send as fast as possible
#   --interval MS     Fixed interval between frames in milliseconds
#
# Examples:
#   sudo ./avtp-canplayer.sh avtp0 /data/candump.log
#   sudo ./avtp-canplayer.sh avtp0 /data/candump.log --speed 2.0
#   sudo ./avtp-canplayer.sh avtp0 /data/candump.log --loop
#   sudo TARGET=1 ./avtp-canplayer.sh eth0 /data/candump.log --no-timestamps
#
# Prerequisites:
#   Dev mode:    docker image available (vep-autosd-runtime:ubi)
#   Target mode: podman image pre-loaded (vep-autosd-runtime:ubi-arm64)

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

# =============================================================================
# Argument parsing
# =============================================================================

if [ $# -lt 2 ]; then
    echo "Usage: sudo $0 <interface> <logfile> [options]"
    echo ""
    echo "IMPORTANT: Requires root/sudo for AF_PACKET raw sockets."
    echo ""
    echo "Arguments:"
    echo "  interface    Ethernet interface for AVTP (e.g., eth0, avtp0)"
    echo "  logfile      Path to candump log file"
    echo ""
    echo "Options (passed to avtp_canplayer):"
    echo "  --speed N         Playback speed multiplier (default: 1.0)"
    echo "  --loop            Loop continuously"
    echo "  --no-timestamps   Ignore timestamps, send as fast as possible"
    echo "  --interval MS     Fixed interval between frames in milliseconds"
    echo ""
    echo "Examples:"
    echo "  sudo $0 avtp0 /data/candump.log"
    echo "  sudo $0 avtp0 /data/candump.log --speed 2.0 --loop"
    echo "  sudo TARGET=1 $0 eth0 /data/candump.log"
    exit 1
fi

AVTP_INTERFACE="$1"
LOGFILE="$2"
shift 2
EXTRA_ARGS="$@"

# Container path for mounted log file
CONTAINER_LOGFILE="/data/candump.log"

# =============================================================================
# Validation
# =============================================================================

# Use path as-is (caller should use $(pwd)/file for absolute path)
if [ ! -f "$LOGFILE" ]; then
    echo "Error: Log file not found: $LOGFILE"
    echo "Hint: Use absolute path, e.g.: sudo $0 $AVTP_INTERFACE \$(pwd)/candump.log"
    exit 1
fi

MODE_DESC="Dev (x86_64)"
[ -n "$TARGET" ] && MODE_DESC="Target (ARM64)"

echo "============================================================"
echo "AVTP CAN Player (containerized)"
echo "============================================================"
echo ""
echo "Configuration:"
echo "  Mode:           $MODE_DESC"
echo "  VEP Image:      $VEP_IMAGE"
echo "  Interface:      $AVTP_INTERFACE"
echo "  Log file:       $LOGFILE"
[ -n "$EXTRA_ARGS" ] && echo "  Options:        $EXTRA_ARGS"
echo ""

# Sync image from docker to podman (dev mode only)
if [ -z "$TARGET" ]; then
    echo "Syncing image from docker to podman..."
    docker save "$VEP_IMAGE" | podman load
    echo ""
fi

echo "Starting avtp_canplayer..."
echo "Press Ctrl+C to stop."
echo "============================================================"
echo ""

# Run container with CAP_NET_RAW for raw Ethernet sockets
podman run --rm \
    $CONTAINER_PLATFORM \
    --network host \
    --cap-add NET_RAW \
    -v "$LOGFILE:$CONTAINER_LOGFILE:ro" \
    "$VEP_IMAGE" \
    avtp_canplayer \
        -I "$CONTAINER_LOGFILE" \
        --interface "$AVTP_INTERFACE" \
        $EXTRA_ARGS

#!/bin/bash
# Replay CAN data from candump log over IEEE 1722 AVTP
# Similar to run_canplayer.sh but sends over Ethernet instead of SocketCAN
#
# Usage:
#   ./run_avtp_canplayer.sh [interface] [logfile]
#
# Examples:
#   ./run_avtp_canplayer.sh                    # Use defaults (eth0, config/candump.log)
#   ./run_avtp_canplayer.sh enp0s3             # Use specific interface
#   ./run_avtp_canplayer.sh eth0 mylog.log     # Use specific interface and log

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
CONFIG_DIR="$SCRIPT_DIR/config"

# Default interface and log file
INTERFACE="${1:-eth0}"
LOGFILE="${2:-$CONFIG_DIR/candump.log}"

# Check if binary exists
CANPLAYER="$BUILD_DIR/libvssdag/tools/avtp_canplayer/avtp_canplayer"
if [ ! -f "$CANPLAYER" ]; then
    echo "Error: avtp_canplayer not found at $CANPLAYER"
    echo "Please build it first: ./build-all.sh"
    exit 1
fi

# Check if log file exists
if [ ! -f "$LOGFILE" ]; then
    echo "Error: Log file not found: $LOGFILE"
    exit 1
fi

echo "=== AVTP CAN Player ==="
echo "Interface: $INTERFACE"
echo "Log file:  $LOGFILE"
echo ""
echo "Note: Raw sockets require CAP_NET_RAW capability or root"
echo ""

# Run with sudo if not root
if [ "$EUID" -ne 0 ]; then
    echo "Running with sudo..."
    sudo "$CANPLAYER" -I "$LOGFILE" --interface "$INTERFACE"
else
    "$CANPLAYER" -I "$LOGFILE" --interface "$INTERFACE"
fi

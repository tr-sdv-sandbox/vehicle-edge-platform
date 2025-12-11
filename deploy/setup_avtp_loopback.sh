#!/bin/bash
# setup_avtp_loopback.sh - Create veth pair for local AVTP testing
#
# This creates two virtual Ethernet interfaces connected to each other:
#   avtp0 <---> avtp1
#
# =============================================================================
# Architecture
# =============================================================================
#
# This simulates the target deployment where:
#   - QNX host sends AVTP frames to a virtual NIC shared with VM
#   - RHEL VM receives on its vNIC
#   - Container (--network host) sees the VM's vNIC
#
# Target setup:
#   ┌─────────────────────────────────────────────────────────┐
#   │ QNX Host                                                │
#   │   CAN HW ──► QNX app ──► AVTP ──► vNIC ────────────────┼──┐
#   │   ┌─────────────────────────────────────────────────┐  │  │
#   │   │ RHEL VM                                         │  │  │
#   │   │   vNIC ◄────────────────────────────────────────┼──┼──┘
#   │   │     │                                           │  │
#   │   │     ▼                                           │  │
#   │   │   Podman: vep_can_probe ──► DDS ──► MQTT        │  │
#   │   └─────────────────────────────────────────────────┘  │
#   └─────────────────────────────────────────────────────────┘
#
# Local simulation with veth:
#   avtp0 (simulates QNX)  <--->  avtp1 (simulates VM's vNIC)
#         │                              │
#         ▼                              ▼
#   avtp_canplayer                vep_can_probe (container)
#
# =============================================================================
# Usage
# =============================================================================
#
#   ./setup_avtp_loopback.sh         # Create veth pair
#   ./setup_avtp_loopback.sh --down  # Remove veth pair
#
# Then in separate terminals:
#
#   # Terminal 1: Start receiver pipeline (listens on avtp1)
#   ./02-avtp-vss-mqtt-chain.sh avtp1
#
#   # Terminal 2: Send CAN data (sends on avtp0)
#   ./avtp-canplayer.sh avtp0 $(pwd)/../config/candump.log
#
# =============================================================================

VETH_TX="avtp0"
VETH_RX="avtp1"

if [ "$1" = "--down" ] || [ "$1" = "down" ] || [ "$1" = "--delete" ]; then
    echo "Removing AVTP veth pair..."
    sudo ip link delete "$VETH_TX" 2>/dev/null || true
    echo "Done."
    exit 0
fi

# Check if already exists
if ip link show "$VETH_TX" &>/dev/null; then
    echo "AVTP veth pair already exists:"
    echo "  TX interface: $VETH_TX (sender)"
    echo "  RX interface: $VETH_RX (receiver)"
    echo ""
    echo "To remove: $0 --down"
    exit 0
fi

echo "Creating AVTP veth pair..."
echo "  $VETH_TX (sender) <---> $VETH_RX (receiver)"
echo ""

# Create veth pair
sudo ip link add "$VETH_TX" type veth peer name "$VETH_RX"

# Bring both interfaces up
sudo ip link set "$VETH_TX" up
sudo ip link set "$VETH_RX" up

# Disable IPv6 to avoid unnecessary traffic
sudo sysctl -q -w net.ipv6.conf.${VETH_TX}.disable_ipv6=1
sudo sysctl -q -w net.ipv6.conf.${VETH_RX}.disable_ipv6=1

echo "AVTP veth pair created successfully!"
echo ""
echo "============================================================"
echo "Quick Start"
echo "============================================================"
echo ""
echo "Terminal 1 - Start receiver pipeline:"
echo "  ./02-avtp-vss-mqtt-chain.sh $VETH_RX"
echo ""
echo "Terminal 2 - Send CAN data:"
echo "  ./avtp-canplayer.sh $VETH_TX \$(pwd)/../config/candump.log"
echo ""
echo "============================================================"
echo ""
echo "To remove veth pair: $0 --down"

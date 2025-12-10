#!/bin/bash
# setup_avtp_loopback.sh - Create veth pair for local AVTP testing
#
# This creates two virtual Ethernet interfaces connected to each other:
#   avtp0 <---> avtp1
#
# Usage:
#   ./setup_avtp_loopback.sh         # Create veth pair
#   ./setup_avtp_loopback.sh --down  # Remove veth pair
#
# Then use:
#   Terminal 1: ./run_framework_avtp.sh avtp1    # Receiver
#   Terminal 2: ./run_avtp_canplayer.sh avtp0    # Sender

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
    echo "  TX interface: $VETH_TX"
    echo "  RX interface: $VETH_RX"
    echo ""
    echo "To remove: $0 --down"
    exit 0
fi

echo "Creating AVTP veth pair..."
echo "  $VETH_TX <---> $VETH_RX"
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
echo "Usage:"
echo "  Terminal 1 (framework): ./run_framework_avtp.sh $VETH_RX"
echo "  Terminal 2 (player):    ./run_avtp_canplayer.sh $VETH_TX"
echo ""
echo "To remove: $0 --down"

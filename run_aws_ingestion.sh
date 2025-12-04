#!/bin/bash
# run_aws_ingestion.sh - Run the cloud backend simulator for AWS ingestion
#
# Usage: ./run_aws_ingestion.sh [--verbose]
#
# This starts the cloud backend simulator which:
#   - Receives MQTT messages from the VDR exporter
#   - Decodes compressed vehicle data
#   - Simulates AWS cloud ingestion pipeline
#
# The simulator connects to Mosquitto broker on localhost:1883

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

# Parse arguments
VERBOSE=""
for arg in "$@"; do
    case $arg in
        --verbose|-v)
            VERBOSE="--verbose"
            ;;
    esac
done

echo "=================================================="
echo "Vehicle Edge Platform - AWS Ingestion Simulator"
echo "=================================================="
echo ""

# Check if build exists
if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory not found. Run './build-all.sh' first."
    exit 1
fi

if [ ! -f "$BUILD_DIR/vep-core/cloud_backend_sim" ]; then
    echo "Error: cloud_backend_sim not found. Run './build-all.sh' first."
    exit 1
fi

# Check Mosquitto broker is running
if systemctl is-active --quiet mosquitto; then
    echo "Mosquitto broker running on localhost:1883"
else
    echo "Warning: Mosquitto broker not running. Start with: sudo systemctl start mosquitto"
fi

echo ""
echo "Starting cloud backend simulator..."
echo "  Subscribing to MQTT topic: vdr/vehicle/+"
echo "  Decoding and displaying vehicle data"
if [ -n "$VERBOSE" ]; then
    echo "  Verbose mode: ON"
fi
echo ""
echo "Press Ctrl+C to stop."
echo ""

# Run the cloud backend simulator (foreground)
exec "$BUILD_DIR/vep-core/cloud_backend_sim" $VERBOSE

#!/bin/bash
# run_aws_ingestion.sh - Run the VEP MQTT receiver for AWS ingestion testing
#
# Usage: ./run_aws_ingestion.sh [--verbose]
#
# This starts the VEP MQTT receiver which:
#   - Receives MQTT messages from the VEP exporter
#   - Decodes compressed vehicle data
#   - Displays telemetry for cloud ingestion testing
#
# The receiver connects to Mosquitto broker on localhost:1883

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

if [ ! -f "$BUILD_DIR/vep-core/vep_mqtt_receiver" ]; then
    echo "Error: vep_mqtt_receiver not found. Run './build-all.sh' first."
    exit 1
fi

# Check Mosquitto broker is running (port 1883)
if nc -z localhost 1883 2>/dev/null; then
    echo "Mosquitto broker running on localhost:1883"
else
    echo "Warning: Mosquitto broker not running."
    echo "  Start the framework first: ./run_framework.sh"
fi

echo ""
echo "Starting VEP MQTT receiver..."
echo "  Subscribing to MQTT topic: v1/telemetry/+"
echo "  Decoding and displaying vehicle data"
if [ -n "$VERBOSE" ]; then
    echo "  Verbose mode: ON"
fi
echo ""
echo "Press Ctrl+C to stop."
echo ""

# Run the MQTT receiver (foreground)
exec "$BUILD_DIR/vep-core/vep_mqtt_receiver" $VERBOSE

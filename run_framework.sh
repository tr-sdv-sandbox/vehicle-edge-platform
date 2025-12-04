#!/bin/bash
# run_framework.sh - Run the VDR framework
#
# Usage: ./run_framework.sh
#
# This starts all framework components:
#   - VDR exporter (DDS -> compressed MQTT)
#   - VSS DAG probe (CAN -> VSS -> DDS)
#
# The probe listens on vcan0 for CAN traffic. Replay with:
#   canplayer -I components/vep-core/config/candump.log vcan0=can0
#
# Press Ctrl+C to stop all services.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
CONFIG_DIR="$SCRIPT_DIR/config"

# PIDs of background processes
PIDS=()

# Track if cleanup already ran
CLEANUP_DONE=false

# Cleanup function
cleanup() {
    # Prevent running cleanup twice
    if [ "$CLEANUP_DONE" = true ]; then
        return
    fi
    CLEANUP_DONE=true

    echo ""
    echo "Stopping services..."

    # Kill background processes with SIGTERM
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "  Stopping PID $pid..."
            kill -TERM "$pid" 2>/dev/null
        fi
    done

    # Give them time to exit gracefully
    sleep 1

    # Force kill any remaining
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "  Force killing PID $pid..."
            kill -9 "$pid" 2>/dev/null
        fi
    done

    # Stop KUKSA databroker container
    if [ -n "$KUKSA_CONTAINER" ]; then
        echo "  Stopping KUKSA databroker container..."
        docker stop --time 1 "$KUKSA_CONTAINER" 2>/dev/null
        docker rm -f "$KUKSA_CONTAINER" 2>/dev/null
    fi

    echo "Framework stopped."
}

# Set trap for cleanup on exit (INT, TERM, and EXIT to catch all cases)
trap cleanup INT TERM EXIT

echo "=================================================="
echo "Vehicle Edge Platform - Framework Runner"
echo "=================================================="
echo ""

# Check if build exists
if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory not found. Run './build-all.sh' first."
    exit 1
fi

# Binaries from vep-core
VDR_EXPORTER="$BUILD_DIR/vep-core/vdr_exporter"
KUKSA_DDS_BRIDGE="$BUILD_DIR/vep-core/kuksa_dds_bridge"
RT_DDS_BRIDGE="$BUILD_DIR/vep-core/rt_dds_bridge"
CLOUD_BACKEND="$BUILD_DIR/vep-core/cloud_backend_sim"

# Probes from vep-core/probes
VSS_CAN_PROBE="$BUILD_DIR/vep-core/probes/vss_can/vdr_vss_can_probe"
OTEL_PROBE="$BUILD_DIR/vep-core/probes/otel/vdr_otel_probe"
AVTP_PROBE="$BUILD_DIR/vep-core/probes/avtp/vdr_avtp_probe"

if [ ! -f "$VDR_EXPORTER" ]; then
    echo "Error: vdr_exporter not found. Run './build-all.sh' first."
    exit 1
fi

if [ ! -f "$VSS_CAN_PROBE" ]; then
    echo "Warning: vdr_vss_can_probe not found at $VSS_CAN_PROBE"
    VSS_CAN_PROBE=""
fi

# Setup vcan0 (always needed for CAN replay)
if ! ip link show vcan0 &>/dev/null; then
    echo "Setting up virtual CAN interface vcan0..."
    sudo modprobe vcan
    sudo ip link add dev vcan0 type vcan
    sudo ip link set up vcan0
    echo "  vcan0 created and up"
else
    echo "  vcan0 already exists"
fi

# Check Mosquitto broker is running
echo ""
if systemctl is-active --quiet mosquitto; then
    echo "Mosquitto broker running on localhost:1883"
else
    echo "Warning: Mosquitto broker not running. Start with: sudo systemctl start mosquitto"
fi

# Start KUKSA databroker (if kuksa_dds_bridge is present)
KUKSA_CONTAINER=""
KUKSA_PORT=61234
if [ -f "$KUKSA_DDS_BRIDGE" ]; then
    echo ""
    echo "Starting KUKSA databroker on port $KUKSA_PORT..."

    # Check if Docker is available
    if ! command -v docker &>/dev/null; then
        echo "Error: Docker not found. KUKSA databroker requires Docker."
        echo "Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi

    # Generate unique container name
    KUKSA_CONTAINER="kuksa-vep-framework-$$"

    # Use our extracted VSS 5.1 JSON (same as KUKSA 0.6.0 built-in, but explicit)
    VSS_JSON="$CONFIG_DIR/vss-5.1-kuksa.json"
    if [ ! -f "$VSS_JSON" ]; then
        echo "Warning: VSS JSON not found: $VSS_JSON"
        echo "  Starting KUKSA with default VSS..."
        docker run -d \
            --name "$KUKSA_CONTAINER" \
            -p $KUKSA_PORT:55555 \
            ghcr.io/eclipse-kuksa/kuksa-databroker:0.6.0 >/dev/null 2>&1
    else
        # Start databroker with our VSS schema
        docker run -d \
            --name "$KUKSA_CONTAINER" \
            -p $KUKSA_PORT:55555 \
            -v "$VSS_JSON:/vss.json:ro" \
            ghcr.io/eclipse-kuksa/kuksa-databroker:0.6.0 \
            --vss /vss.json >/dev/null 2>&1
    fi

    if [ $? -ne 0 ]; then
        echo "Error: Failed to start KUKSA databroker"
        echo "Try: docker pull ghcr.io/eclipse-kuksa/kuksa-databroker:0.6.0"
        exit 1
    fi

    echo "  KUKSA databroker running (container: $KUKSA_CONTAINER)"

    # Wait for databroker to be ready
    echo "  Waiting for databroker to be ready..."
    for i in $(seq 1 20); do
        if nc -z localhost $KUKSA_PORT 2>/dev/null; then
            echo "  KUKSA databroker ready on localhost:$KUKSA_PORT"
            break
        fi
        sleep 0.5
    done

    if ! nc -z localhost $KUKSA_PORT 2>/dev/null; then
        echo "Error: KUKSA databroker failed to start"
        docker logs "$KUKSA_CONTAINER"
        docker rm -f "$KUKSA_CONTAINER" 2>/dev/null
        exit 1
    fi
fi

echo ""

# Start VDR exporter
echo "Starting VDR exporter..."
"$VDR_EXPORTER" &
PIDS+=($!)
echo "  vdr_exporter running (PID ${PIDS[-1]})"

sleep 1

# Start VSS CAN probe (CAN-to-VSS)
if [ -n "$VSS_CAN_PROBE" ]; then
    echo "Starting vdr_vss_can_probe (CAN -> VSS -> DDS)..."
    "$VSS_CAN_PROBE" \
        --config "$CONFIG_DIR/model3_mappings_dag.yaml" \
        --interface vcan0 \
        --dbc "$CONFIG_DIR/Model3CAN.dbc" &
    PIDS+=($!)
    echo "  vdr_vss_can_probe running (PID ${PIDS[-1]})"
fi

# Start RT-DDS bridge (DDS <-> RT transport, loopback mode for simulation)
if [ -f "$RT_DDS_BRIDGE" ]; then
    echo "Starting rt_dds_bridge (DDS <-> RT loopback)..."
    "$RT_DDS_BRIDGE" \
        --transport=loopback \
        --loopback_delay_ms=50 &
    PIDS+=($!)
    echo "  rt_dds_bridge running (PID ${PIDS[-1]})"
fi

sleep 1

# Start Kuksa-DDS bridge (Kuksa <-> DDS)
if [ -f "$KUKSA_DDS_BRIDGE" ] && [ -n "$KUKSA_CONTAINER" ]; then
    echo "Starting kuksa_dds_bridge (Kuksa <-> DDS)..."
    "$KUKSA_DDS_BRIDGE" \
        --kuksa=localhost:$KUKSA_PORT &
    PIDS+=($!)
    echo "  kuksa_dds_bridge running (PID ${PIDS[-1]})"
fi

echo ""
echo "=================================================="
echo "Framework running!"
echo "=================================================="
echo ""
echo "Services:"
echo "  - Mosquitto MQTT broker: localhost:1883"
echo "  - VDR Exporter: subscribing to DDS, publishing to MQTT"
if [ -n "$VSS_CAN_PROBE" ]; then
    echo "  - VSS CAN Probe: listening on vcan0 for CAN traffic"
fi
if [ -n "$KUKSA_CONTAINER" ]; then
    echo "  - KUKSA Databroker: localhost:$KUKSA_PORT (container: $KUKSA_CONTAINER)"
fi
if [ -f "$RT_DDS_BRIDGE" ]; then
    echo "  - RT-DDS Bridge: loopback mode (echoes actuator targets as actuals)"
fi
if [ -f "$KUKSA_DDS_BRIDGE" ] && [ -n "$KUKSA_CONTAINER" ]; then
    echo "  - Kuksa-DDS Bridge: bridging Kuksa databroker <-> DDS"
fi
echo ""
echo "To replay CAN data:"
echo "  ./run_canplayer.sh"
echo ""
echo "To view cloud backend messages:"
echo "  $CLOUD_BACKEND"
echo ""
echo "Press Ctrl+C to stop all services."
echo ""

# Wait for all background processes
while true; do
    # Check if any process is still running
    alive=false
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            alive=true
            break
        fi
    done

    if [ "$alive" = false ]; then
        echo "All processes exited."
        break
    fi

    sleep 1
done

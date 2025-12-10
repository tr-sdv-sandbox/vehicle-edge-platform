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

    # Stop Mosquitto container
    if [ -n "$MOSQUITTO_CONTAINER" ]; then
        echo "  Stopping Mosquitto container..."
        docker stop --time 1 "$MOSQUITTO_CONTAINER" 2>/dev/null
        docker rm -f "$MOSQUITTO_CONTAINER" 2>/dev/null
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
VEP_EXPORTER="$BUILD_DIR/vep-core/vep_exporter"
KUKSA_DDS_BRIDGE="$BUILD_DIR/vep-core/kuksa_dds_bridge"
RT_DDS_BRIDGE="$BUILD_DIR/vep-core/rt_dds_bridge"
VEP_MQTT_RECEIVER="$BUILD_DIR/vep-core/vep_mqtt_receiver"

# Probes from vep-core/probes
VEP_CAN_PROBE="$BUILD_DIR/vep-core/probes/vep_can_probe/vep_can_probe"
VEP_OTEL_PROBE="$BUILD_DIR/vep-core/probes/vep_otel_probe/vep_otel_probe"
VEP_AVTP_PROBE="$BUILD_DIR/vep-core/probes/vep_avtp_probe/vep_avtp_probe"

# Tools
VEP_HOST_METRICS="$BUILD_DIR/vep-core/tools/vep_host_metrics/vep_host_metrics"

if [ ! -f "$VEP_EXPORTER" ]; then
    echo "Error: vep_exporter not found. Run './build-all.sh' first."
    exit 1
fi

if [ ! -f "$VEP_CAN_PROBE" ]; then
    echo "Warning: vep_can_probe not found at $VEP_CAN_PROBE"
    VEP_CAN_PROBE=""
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

# Start Mosquitto MQTT broker
MOSQUITTO_CONTAINER=""
MOSQUITTO_PORT=1883
echo ""
echo "Starting Mosquitto MQTT broker on port $MOSQUITTO_PORT..."

# Generate unique container name
MOSQUITTO_CONTAINER="mosquitto-vep-framework-$$"

# Start Mosquitto with anonymous access enabled (listener + allow_anonymous)
docker run -d \
    --name "$MOSQUITTO_CONTAINER" \
    -p $MOSQUITTO_PORT:1883 \
    eclipse-mosquitto:2 \
    sh -c 'echo -e "listener 1883\nallow_anonymous true" > /tmp/mosquitto.conf && mosquitto -c /tmp/mosquitto.conf' >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "Error: Failed to start Mosquitto broker"
    echo "Try: docker pull eclipse-mosquitto:2"
    exit 1
fi

echo "  Mosquitto broker running (container: $MOSQUITTO_CONTAINER)"

# Wait for Mosquitto to be ready
echo "  Waiting for Mosquitto to be ready..."
for i in $(seq 1 10); do
    if nc -z localhost $MOSQUITTO_PORT 2>/dev/null; then
        echo "  Mosquitto broker ready on localhost:$MOSQUITTO_PORT"
        break
    fi
    sleep 0.5
done

if ! nc -z localhost $MOSQUITTO_PORT 2>/dev/null; then
    echo "Error: Mosquitto broker failed to start"
    docker logs "$MOSQUITTO_CONTAINER"
    docker rm -f "$MOSQUITTO_CONTAINER" 2>/dev/null
    exit 1
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

# Start VEP exporter
echo "Starting VEP exporter..."
"$VEP_EXPORTER" &
PIDS+=($!)
echo "  vep_exporter running (PID ${PIDS[-1]})"

sleep 1

# Start VEP CAN probe (CAN-to-VSS)
if [ -n "$VEP_CAN_PROBE" ]; then
    echo "Starting vep_can_probe (CAN -> VSS -> DDS)..."
    "$VEP_CAN_PROBE" \
        --config "$CONFIG_DIR/model3_mappings_dag.yaml" \
        --interface vcan0 \
        --dbc "$CONFIG_DIR/Model3CAN.dbc" &
    PIDS+=($!)
    echo "  vep_can_probe running (PID ${PIDS[-1]})"
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

# Start OTEL probe (OTLP gRPC -> DDS)
if [ -f "$VEP_OTEL_PROBE" ]; then
    echo "Starting vep_otel_probe (OTLP gRPC -> DDS)..."
    "$VEP_OTEL_PROBE" &
    PIDS+=($!)
    echo "  vep_otel_probe running (PID ${PIDS[-1]})"
    sleep 1  # Give it time to start listening
fi

# Start host metrics collector (Linux metrics -> OTLP gRPC)
if [ -f "$VEP_HOST_METRICS" ] && [ -f "$VEP_OTEL_PROBE" ]; then
    echo "Starting vep_host_metrics (Linux metrics -> OTLP)..."
    "$VEP_HOST_METRICS" \
        --endpoint localhost:4317 \
        --interval 10 &
    PIDS+=($!)
    echo "  vep_host_metrics running (PID ${PIDS[-1]})"
fi

echo ""
echo "=================================================="
echo "Framework running!"
echo "=================================================="
echo ""
echo "Services:"
echo "  - Mosquitto MQTT broker: localhost:$MOSQUITTO_PORT (container: $MOSQUITTO_CONTAINER)"
echo "  - VEP Exporter: subscribing to DDS, publishing to MQTT"
if [ -n "$VEP_CAN_PROBE" ]; then
    echo "  - VEP CAN Probe: listening on vcan0 for CAN traffic"
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
if [ -f "$VEP_OTEL_PROBE" ]; then
    echo "  - VEP OTEL Probe: receiving OTLP metrics on localhost:4317 -> DDS"
fi
if [ -f "$VEP_HOST_METRICS" ] && [ -f "$VEP_OTEL_PROBE" ]; then
    echo "  - VEP Host Metrics: collecting CPU/memory/disk/network every 10s"
fi
echo ""
echo "To replay CAN data:"
echo "  ./run_canplayer.sh"
echo ""
echo "To view MQTT messages:"
echo "  $VEP_MQTT_RECEIVER"
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

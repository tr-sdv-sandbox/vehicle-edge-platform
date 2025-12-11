#!/bin/bash
# 02-avtp-vss-mqtt-chain.sh - Full VEP telemetry pipeline with AVTP CAN transport
#
# Runs the complete vehicle telemetry pipeline with IEEE 1722 AVTP transport:
#   - AVTP CAN frames -> vep_can_probe -> VSS -> DDS
#   - Host metrics -> vep_otel_probe -> DDS
#   - DDS -> vep_exporter -> MQTT -> vep_mqtt_receiver
#
# IMPORTANT: This script requires root/sudo to create AF_PACKET raw sockets for AVTP.
#   Rootless podman cannot grant CAP_NET_RAW to containers.
#
# Usage:
#   sudo ./02-avtp-vss-mqtt-chain.sh [interface]              # Dev mode (x86_64)
#   sudo TARGET=1 ./02-avtp-vss-mqtt-chain.sh [interface]     # Target mode (ARM64)
#
# Environment variables:
#   TARGET=1              Enable ARM64 target mode
#   DBC_FILE=path         Path to DBC file (default: config/Model3CAN.dbc)
#   MAPPINGS_FILE=path    Path to mappings YAML (default: config/model3_mappings_dag.yaml)
#   MQTT_PORT=1883        MQTT broker port
#
# Examples:
#   sudo ./02-avtp-vss-mqtt-chain.sh eth0
#   sudo DBC_FILE=/my/custom.dbc MAPPINGS_FILE=/my/mappings.yaml ./02-avtp-vss-mqtt-chain.sh eth0
#   sudo TARGET=1 DBC_FILE=/data/j1939.dbc ./02-avtp-vss-mqtt-chain.sh can0
#
# Prerequisites:
#   Dev mode:    docker images available (vep-autosd-runtime:ubi, eclipse-mosquitto:2)
#   Target mode: podman images pre-loaded (use pull-mosquitto-arm64.sh + push-image-to-target.sh)
#
# To send CAN data, run in another terminal:
#   sudo ./avtp-canplayer.sh avtp0 /path/to/candump.log
#
# Press Ctrl+C to stop all services.

set -e

# =============================================================================
# Configuration - adjust for your environment
# =============================================================================

# TARGET mode: set to "1" for ARM64 target deployment
TARGET="${TARGET:-}"

# Ethernet interface for AVTP (can be overridden by first argument)
AVTP_INTERFACE="${1:-eth0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"

# CAN/VSS configuration files (configurable via environment)
DBC_FILE="${DBC_FILE:-$CONFIG_DIR/Model3CAN.dbc}"
MAPPINGS_FILE="${MAPPINGS_FILE:-$CONFIG_DIR/model3_mappings_dag.yaml}"

if [ -n "$TARGET" ]; then
    # Target deployment (ARM64)
    VEP_IMAGE="docker.io/library/vep-autosd-runtime:ubi-arm64"
    MOSQUITTO_IMAGE="docker.io/eclipse-mosquitto:2"
    CONTAINER_PLATFORM="--arch arm64"
else
    # Dev deployment (x86_64)
    VEP_IMAGE="vep-autosd-runtime:ubi"
    MOSQUITTO_IMAGE="docker.io/eclipse-mosquitto:2"
    CONTAINER_PLATFORM=""
fi

# MQTT settings
MQTT_BROKER="localhost"
MQTT_PORT="${MQTT_PORT:-1883}"

# OTEL settings
OTEL_GRPC_PORT="4317"
HOST_METRICS_INTERVAL="5"                    # Seconds between metrics collection

# Container paths for mounted config files
CONTAINER_DBC_FILE="/etc/vep/can.dbc"
CONTAINER_MAPPINGS_FILE="/etc/vep/mappings.yaml"

# Container naming prefix (for cleanup)
CONTAINER_PREFIX="vep-avtp-$$"

# =============================================================================
# End of configuration
# =============================================================================

# Track containers for cleanup
CONTAINERS=()

cleanup() {
    echo ""
    echo "Stopping services..."

    for container in "${CONTAINERS[@]}"; do
        if podman ps -q -f name="$container" 2>/dev/null | grep -q .; then
            echo "  Stopping $container..."
            podman stop -t 2 "$container" 2>/dev/null || true
            podman rm -f "$container" 2>/dev/null || true
        fi
    done

    echo "Stopped."
}

trap cleanup INT TERM EXIT

MODE_DESC="Dev (x86_64)"
[ -n "$TARGET" ] && MODE_DESC="Target (ARM64)"

echo "============================================================"
echo "VEP Deployment: AVTP CAN -> VSS -> MQTT Chain"
echo "============================================================"
echo ""
echo "Configuration:"
echo "  Mode:           $MODE_DESC"
echo "  VEP Image:      $VEP_IMAGE"
echo "  Mosquitto:      $MOSQUITTO_IMAGE"
echo "  AVTP Interface: $AVTP_INTERFACE"
echo "  DBC File:       $DBC_FILE"
echo "  Mappings:       $MAPPINGS_FILE"
echo "  MQTT Broker:    $MQTT_BROKER:$MQTT_PORT"
echo ""

# Check config files exist
if [ ! -f "$DBC_FILE" ]; then
    echo "Error: DBC file not found: $DBC_FILE"
    echo "Set DBC_FILE environment variable to specify a different file."
    exit 1
fi
if [ ! -f "$MAPPINGS_FILE" ]; then
    echo "Error: Mappings file not found: $MAPPINGS_FILE"
    echo "Set MAPPINGS_FILE environment variable to specify a different file."
    exit 1
fi

# Sync images from docker to podman (dev mode only)
if [ -z "$TARGET" ]; then
    echo "Syncing images from docker to podman..."
    docker save "$VEP_IMAGE" | podman load
    docker save "$MOSQUITTO_IMAGE" | podman load
    echo ""
fi

# -----------------------------------------------------------------------------
# Step 1: Start MQTT Broker
# -----------------------------------------------------------------------------
echo "[1/6] Starting MQTT broker..."

MQTT_CONTAINER="${CONTAINER_PREFIX}-mqtt"
CONTAINERS+=("$MQTT_CONTAINER")

podman run -d \
    --name "$MQTT_CONTAINER" \
    $CONTAINER_PLATFORM \
    --network host \
    "$MOSQUITTO_IMAGE" \
    sh -c 'echo -e "listener 1883\nallow_anonymous true" > /tmp/mosquitto.conf && mosquitto -c /tmp/mosquitto.conf'

# Wait for broker to be ready
echo "  Waiting for MQTT broker..."
for i in $(seq 1 10); do
    if nc -z $MQTT_BROKER $MQTT_PORT 2>/dev/null; then
        echo "  MQTT broker ready on $MQTT_BROKER:$MQTT_PORT"
        break
    fi
    sleep 0.5
done
echo ""

# -----------------------------------------------------------------------------
# Step 2: Start VEP Exporter (DDS -> MQTT)
# -----------------------------------------------------------------------------
echo "[2/6] Starting vep_exporter (DDS -> MQTT)..."

EXPORTER_CONTAINER="${CONTAINER_PREFIX}-exporter"
CONTAINERS+=("$EXPORTER_CONTAINER")

podman run -d \
    --name "$EXPORTER_CONTAINER" \
    $CONTAINER_PLATFORM \
    --network host \
    "$VEP_IMAGE" \
    vep_exporter \
        --broker $MQTT_BROKER \
        --port $MQTT_PORT

echo "  vep_exporter started"
echo ""

# -----------------------------------------------------------------------------
# Step 3: Start VEP OTEL Probe (OTLP gRPC -> DDS)
# -----------------------------------------------------------------------------
echo "[3/6] Starting vep_otel_probe (OTLP gRPC -> DDS)..."

OTEL_PROBE_CONTAINER="${CONTAINER_PREFIX}-otel-probe"
CONTAINERS+=("$OTEL_PROBE_CONTAINER")

podman run -d \
    --name "$OTEL_PROBE_CONTAINER" \
    $CONTAINER_PLATFORM \
    --network host \
    "$VEP_IMAGE" \
    vep_otel_probe \
        --port $OTEL_GRPC_PORT

echo "  vep_otel_probe listening on port $OTEL_GRPC_PORT"
sleep 1  # Give it time to start listening
echo ""

# -----------------------------------------------------------------------------
# Step 4: Start VEP Host Metrics (Linux metrics -> OTLP)
# -----------------------------------------------------------------------------
echo "[4/6] Starting vep_host_metrics (Linux metrics -> OTLP)..."

HOST_METRICS_CONTAINER="${CONTAINER_PREFIX}-host-metrics"
CONTAINERS+=("$HOST_METRICS_CONTAINER")

# Mount /proc and /sys read-only for host metrics collection
podman run -d \
    --name "$HOST_METRICS_CONTAINER" \
    $CONTAINER_PLATFORM \
    --network host \
    -v /proc:/host/proc:ro \
    -v /sys:/host/sys:ro \
    -e HOST_PROC=/host/proc \
    -e HOST_SYS=/host/sys \
    "$VEP_IMAGE" \
    vep_host_metrics \
        --endpoint localhost:$OTEL_GRPC_PORT \
        --interval $HOST_METRICS_INTERVAL

echo "  vep_host_metrics collecting every ${HOST_METRICS_INTERVAL}s"
echo ""

# -----------------------------------------------------------------------------
# Step 5: Start VEP CAN Probe with AVTP transport (AVTP -> VSS -> DDS)
# -----------------------------------------------------------------------------
echo "[5/6] Starting vep_can_probe (AVTP -> VSS -> DDS)..."

CAN_PROBE_CONTAINER="${CONTAINER_PREFIX}-can-probe"
CONTAINERS+=("$CAN_PROBE_CONTAINER")

# Mount config files and run with CAP_NET_RAW for raw Ethernet sockets
podman run -d \
    --name "$CAN_PROBE_CONTAINER" \
    $CONTAINER_PLATFORM \
    --network host \
    --cap-add NET_RAW \
    -v "$DBC_FILE:$CONTAINER_DBC_FILE:ro" \
    -v "$MAPPINGS_FILE:$CONTAINER_MAPPINGS_FILE:ro" \
    "$VEP_IMAGE" \
    vep_can_probe \
        --config "$CONTAINER_MAPPINGS_FILE" \
        --dbc "$CONTAINER_DBC_FILE" \
        --interface "$AVTP_INTERFACE" \
        --transport avtp

echo "  vep_can_probe listening on $AVTP_INTERFACE for IEEE 1722 AVTP CAN frames"
sleep 1
echo ""

# -----------------------------------------------------------------------------
# Step 6: Start VEP MQTT Receiver (display MQTT messages)
# -----------------------------------------------------------------------------
echo "[6/6] Starting vep_mqtt_receiver (MQTT -> display)..."
echo ""

RECEIVER_CONTAINER="${CONTAINER_PREFIX}-receiver"
CONTAINERS+=("$RECEIVER_CONTAINER")

echo "============================================================"
echo "Pipeline running!"
echo "============================================================"
echo ""
echo "Services:"
echo "  - MQTT broker:       $MQTT_BROKER:$MQTT_PORT"
echo "  - vep_exporter:      DDS -> MQTT"
echo "  - vep_otel_probe:    OTLP gRPC :$OTEL_GRPC_PORT -> DDS"
echo "  - vep_host_metrics:  Linux metrics -> OTLP (every ${HOST_METRICS_INTERVAL}s)"
echo "  - vep_can_probe:     AVTP ($AVTP_INTERFACE) -> VSS -> DDS"
echo "  - vep_mqtt_receiver: MQTT -> display"
echo ""
echo "To send CAN data over AVTP (in another terminal):"
echo "  sudo ./avtp-canplayer.sh avtp0 /path/to/candump.log"
echo ""
echo "Signals should appear below (host metrics every ${HOST_METRICS_INTERVAL}s, VSS when CAN data received)."
echo "Press Ctrl+C to stop all services."
echo "============================================================"
echo ""

# Run receiver in foreground so we can see output
podman run \
    --name "$RECEIVER_CONTAINER" \
    $CONTAINER_PLATFORM \
    --network host \
    "$VEP_IMAGE" \
    vep_mqtt_receiver \
        --broker $MQTT_BROKER \
        --port $MQTT_PORT

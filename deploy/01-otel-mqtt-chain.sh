#!/bin/bash
# 01-otel-mqtt-chain.sh - OTEL metrics -> DDS -> MQTT chain
#
# Tests the complete telemetry pipeline:
#   vep_host_metrics -> OTLP gRPC -> vep_otel_probe -> DDS -> vep_exporter -> MQTT -> vep_mqtt_receiver
#
# Usage:
#   ./01-otel-mqtt-chain.sh              # Dev mode (x86_64)
#   TARGET=1 ./01-otel-mqtt-chain.sh     # Target mode (ARM64)
#
# Prerequisites:
#   Dev mode:    docker images available (vep-autosd-runtime:ubi, eclipse-mosquitto:2)
#   Target mode: podman images pre-loaded (use pull-mosquitto-arm64.sh + push-image-to-target.sh)
#
# Press Ctrl+C to stop all services.

set -e

# =============================================================================
# Configuration - adjust for your environment
# =============================================================================

# TARGET mode: set to "1" for ARM64 target deployment
# Dev mode (default): x86_64 containers
# Target mode: ARM64 containers
TARGET="${TARGET:-}"

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

# Container naming prefix (for cleanup)
CONTAINER_PREFIX="vep-deploy-$$"

# =============================================================================
# End of configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
echo "VEP Deployment: OTEL -> MQTT Chain"
echo "============================================================"
echo ""
echo "Configuration:"
echo "  Mode:           $MODE_DESC"
echo "  VEP Image:      $VEP_IMAGE"
echo "  Mosquitto:      $MOSQUITTO_IMAGE"
echo "  MQTT Broker:    $MQTT_BROKER:$MQTT_PORT"
echo ""

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
echo "[1/5] Starting MQTT broker..."

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
echo "[2/5] Starting vep_exporter (DDS -> MQTT)..."

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
echo "[3/5] Starting vep_otel_probe (OTLP gRPC -> DDS)..."

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
echo "[4/5] Starting vep_host_metrics (Linux metrics -> OTLP)..."

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
# Step 5: Start VEP MQTT Receiver (display MQTT messages)
# -----------------------------------------------------------------------------
echo "[5/5] Starting vep_mqtt_receiver (MQTT -> display)..."
echo ""

RECEIVER_CONTAINER="${CONTAINER_PREFIX}-receiver"
CONTAINERS+=("$RECEIVER_CONTAINER")

echo "============================================================"
echo "Pipeline running! Metrics should appear below."
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

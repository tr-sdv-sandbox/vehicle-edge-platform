#!/bin/bash
# 04-auto-pipeline.sh - Complete VEP telemetry pipeline with auto architecture detection
#
# Automatically detects host architecture and selects appropriate container images.
# Works on: Linux x86_64, Linux ARM64, macOS ARM64 (Apple Silicon)
#
# Config files are expected in a config subdirectory (default: config_tesla/).
# Copy config files there for deployment:
#   config_tesla/Model3CAN.dbc (or your DBC file)
#   config_tesla/model3_mappings_dag.yaml (or your mappings)
#   config_tesla/vss-5.1-kuksa.json (VSS schema)
#   config_tesla/candump.log (for testing with avtp-canplayer.sh)
#
# Usage:
#   sudo ./04-auto-pipeline.sh [interface]
#
# Environment variables:
#   CONFIG_DIR=path            Config directory (default: ./config_tesla)
#   DBC_FILE=path              Path to DBC file (default: $CONFIG_DIR/Model3CAN.dbc)
#   MAPPINGS_FILE=path         Path to mappings YAML (default: $CONFIG_DIR/model3_mappings_dag.yaml)
#   VSS_FILE=path              Path to VSS JSON (default: $CONFIG_DIR/vss-5.1-kuksa.json)
#   MQTT_PORT=1883             MQTT broker port
#   KUKSA_PORT=55555           KUKSA databroker port
#   KUKSA_TIMEOUT=120          Timeout for KUKSA bridge ready (seconds)
#   OTEL_GRPC_PORT=4317        OpenTelemetry gRPC port
#   HOST_METRICS_INTERVAL=5    Host metrics collection interval (seconds)
#   RT_LOOPBACK_DELAY_MS=50    RT bridge loopback delay (milliseconds)
#
# Examples:
#   sudo ./04-auto-pipeline.sh eth0
#   sudo ./04-auto-pipeline.sh avtp1
#
# Target Deployment:
#   1. Sync deploy directory to target:
#      rsync -av deploy/ target:/opt/vep/
#
#   2. On target, run the pipeline:
#      cd /opt/vep && sudo ./04-auto-pipeline.sh avtp1
#
#   3. Send CAN data (from another terminal):
#      sudo ./avtp-canplayer.sh avtp0 $(pwd)/config_tesla/candump.log
#
# Press Ctrl+C to stop all services.

set -e

# =============================================================================
# Architecture Detection
# =============================================================================

detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)   echo "amd64" ;;
        aarch64|arm64)  echo "arm64" ;;
        *)
            echo "Error: Unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac
}

detect_os() {
    case "$(uname -s)" in
        Linux)  echo "linux" ;;
        Darwin) echo "darwin" ;;
        *)      echo "linux" ;;
    esac
}

HOST_ARCH=$(detect_arch)
HOST_OS=$(detect_os)

# Target = Linux ARM64 (embedded, airgapped)
# Dev machine = everything else (Darwin, Linux x86_64, WSL, etc.)
IS_TARGET=false
[ "$HOST_OS" = "linux" ] && [ "$HOST_ARCH" = "arm64" ] && IS_TARGET=true

# =============================================================================
# Configuration
# =============================================================================

AVTP_INTERFACE="${1:-avtp1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Config files - default to config/ subdirectory (copy files there for deployment)
CONFIG_DIR="${CONFIG_DIR:-$SCRIPT_DIR/config_tesla}"
DBC_FILE="${DBC_FILE:-$CONFIG_DIR/Model3CAN.dbc}"
MAPPINGS_FILE="${MAPPINGS_FILE:-$CONFIG_DIR/model3_mappings_dag.yaml}"
VSS_FILE="${VSS_FILE:-$CONFIG_DIR/vss-5.1-kuksa.json}"

# Select images based on detected architecture
if [ "$HOST_ARCH" = "arm64" ]; then
    VEP_IMAGE="docker.io/library/vep-autosd-runtime:ubi-arm64"
    MOSQUITTO_IMAGE="docker.io/arm64v8/eclipse-mosquitto:2"
    KUKSA_IMAGE="ghcr.io/eclipse-kuksa/kuksa-databroker:0.6.0"
    CONTAINER_PLATFORM="--arch arm64"
    MODE_DESC="ARM64 ($HOST_OS)"
else
    VEP_IMAGE="vep-autosd-runtime:ubi"
    MOSQUITTO_IMAGE="docker.io/eclipse-mosquitto:2"
    KUKSA_IMAGE="ghcr.io/eclipse-kuksa/kuksa-databroker:0.6.0"
    CONTAINER_PLATFORM="--arch amd64"
    MODE_DESC="x86_64 ($HOST_OS)"
fi

# Targets are airgapped - never pull
if [ "$IS_TARGET" = "true" ]; then
    PULL_POLICY="--pull=never"
else
    PULL_POLICY=""
fi

# Ports
MQTT_BROKER="localhost"
MQTT_PORT="${MQTT_PORT:-1883}"
KUKSA_PORT="${KUKSA_PORT:-55555}"
KUKSA_TIMEOUT="${KUKSA_TIMEOUT:-120}"
OTEL_GRPC_PORT="${OTEL_GRPC_PORT:-4317}"
HOST_METRICS_INTERVAL="${HOST_METRICS_INTERVAL:-5}"
RT_LOOPBACK_DELAY_MS="${RT_LOOPBACK_DELAY_MS:-50}"

# Container paths
CONTAINER_DBC_FILE="/etc/vep/can.dbc"
CONTAINER_MAPPINGS_FILE="/etc/vep/mappings.yaml"
CONTAINER_VSS_FILE="/etc/vep/vss.json"
CONTAINER_PREFIX="vep-auto-$$"

# =============================================================================
# Pre-flight checks
# =============================================================================

# Clean up stale containers FIRST (they may be holding ports)
echo "Cleaning up stale containers..."
STALE=$(podman ps -aq --filter "name=vep-auto" 2>/dev/null)
[ -n "$STALE" ] && podman rm -f $STALE 2>/dev/null || true

# Port check function - uses ss (more reliable than nc)
port_in_use() {
    local port=$1
    ss -tuln 2>/dev/null | grep -q ":${port} " && return 0
    nc -z localhost "$port" 2>/dev/null && return 0
    return 1
}

# Wait for port to be free (max 10 seconds)
wait_port_free() {
    local port=$1
    local attempts=0
    local max=10
    while port_in_use "$port"; do
        attempts=$((attempts + 1))
        if [ $attempts -ge $max ]; then
            echo "Error: Port $port still in use"
            echo "Check: ss -tuln | grep $port"
            echo "Try:   sudo podman rm -f \$(sudo podman ps -aq)"
            return 1
        fi
        echo "  Port $port in use, waiting... ($attempts/$max)"
        sleep 1
    done
    return 0
}

# Start container with failure detection
start_container() {
    local name=$1
    shift
    if ! podman run -d --name "$name" "$@"; then
        echo "Error: Failed to start container $name"
        podman logs "$name" 2>/dev/null || true
        return 1
    fi
    # Brief check that container is still running
    sleep 0.5
    if ! podman ps -q --filter "name=$name" | grep -q .; then
        echo "Error: Container $name exited immediately"
        podman logs "$name" 2>/dev/null || true
        return 1
    fi
    return 0
}

echo "Checking port availability..."
wait_port_free $KUKSA_PORT || exit 1
wait_port_free $MQTT_PORT || exit 1
echo "  Ports available"
echo ""

# Track containers for cleanup
CONTAINERS=()
cleanup() {
    echo ""
    echo "Stopping services..."
    for c in "${CONTAINERS[@]}"; do
        podman stop -t 2 "$c" 2>/dev/null || true
        podman rm -f "$c" 2>/dev/null || true
    done
    echo "Stopped."
}
trap cleanup INT TERM EXIT

# =============================================================================
# Display configuration
# =============================================================================

echo "============================================================"
echo "VEP Pipeline (Auto Architecture)"
echo "============================================================"
echo ""
echo "Detected:  $HOST_ARCH / $HOST_OS"
echo "Mode:      $MODE_DESC"
if [ "$IS_TARGET" = "true" ]; then
    echo "Type:      Target (airgapped, no image pulls)"
else
    echo "Type:      Dev machine (will sync/pull images)"
fi
echo ""
echo "Images:"
echo "  VEP:        $VEP_IMAGE"
echo "  Mosquitto:  $MOSQUITTO_IMAGE"
echo "  KUKSA:      $KUKSA_IMAGE"
echo ""
echo "Config:"
echo "  Directory:  $CONFIG_DIR"
echo "  Interface:  $AVTP_INTERFACE"
echo "  DBC:        $DBC_FILE"
echo "  Mappings:   $MAPPINGS_FILE"
echo "  VSS:        $VSS_FILE"
echo "  KUKSA:      localhost:$KUKSA_PORT (timeout: ${KUKSA_TIMEOUT}s)"
echo "  MQTT:       $MQTT_BROKER:$MQTT_PORT"
echo ""

# Check config files
if [ ! -f "$DBC_FILE" ]; then
    echo "Error: DBC file not found: $DBC_FILE"
    echo "Copy your DBC file to: $CONFIG_DIR/"
    exit 1
fi
if [ ! -f "$MAPPINGS_FILE" ]; then
    echo "Error: Mappings file not found: $MAPPINGS_FILE"
    echo "Copy your mappings file to: $CONFIG_DIR/"
    exit 1
fi

# Dev machines: sync VEP from docker, pull public images if needed
if [ "$IS_TARGET" = "false" ]; then
    # Sync VEP from docker (might have just rebuilt)
    if command -v docker &>/dev/null; then
        echo "Syncing VEP image from docker to podman..."
        docker save "$VEP_IMAGE" 2>/dev/null | podman load 2>/dev/null || true
    fi

    # Pull public images if not present
    if ! podman image exists "$MOSQUITTO_IMAGE" 2>/dev/null; then
        echo "Pulling $MOSQUITTO_IMAGE..."
        podman pull "$MOSQUITTO_IMAGE"
    fi
    if ! podman image exists "$KUKSA_IMAGE" 2>/dev/null; then
        echo "Pulling $KUKSA_IMAGE..."
        podman pull "$KUKSA_IMAGE"
    fi
    echo ""
fi

# Verify all required images exist
echo "Verifying images..."
MISSING_IMAGES=false
for img in "$VEP_IMAGE" "$MOSQUITTO_IMAGE" "$KUKSA_IMAGE"; do
    if ! podman image exists "$img" 2>/dev/null; then
        echo "  Error: Image not found: $img"
        MISSING_IMAGES=true
    fi
done
if [ "$MISSING_IMAGES" = "true" ]; then
    if [ "$IS_TARGET" = "true" ]; then
        echo "On target, load images with: podman load < image.tar"
    fi
    exit 1
fi
echo "  All images available"
echo ""

# =============================================================================
# Start services
# =============================================================================

# 1. MQTT Broker
echo "[1/9] Starting MQTT broker..."
MQTT_CONTAINER="${CONTAINER_PREFIX}-mqtt"
CONTAINERS+=("$MQTT_CONTAINER")
start_container "$MQTT_CONTAINER" $CONTAINER_PLATFORM $PULL_POLICY --network host \
    "$MOSQUITTO_IMAGE" \
    sh -c 'echo -e "listener 1883\nallow_anonymous true" > /tmp/m.conf && mosquitto -c /tmp/m.conf' || exit 1
for i in $(seq 1 10); do nc -z $MQTT_BROKER $MQTT_PORT 2>/dev/null && break; sleep 0.5; done
echo "  MQTT ready"

# 2. KUKSA Databroker
echo "[2/9] Starting KUKSA databroker..."
KUKSA_CONTAINER="${CONTAINER_PREFIX}-kuksa"
CONTAINERS+=("$KUKSA_CONTAINER")
if [ -f "$VSS_FILE" ]; then
    start_container "$KUKSA_CONTAINER" $CONTAINER_PLATFORM $PULL_POLICY --network host \
        -v "$VSS_FILE:$CONTAINER_VSS_FILE:ro,z" \
        "$KUKSA_IMAGE" --address 0.0.0.0 --port $KUKSA_PORT --insecure --vss "$CONTAINER_VSS_FILE" || exit 1
else
    echo "  Warning: VSS file not found, using default"
    start_container "$KUKSA_CONTAINER" $CONTAINER_PLATFORM $PULL_POLICY --network host \
        "$KUKSA_IMAGE" --address 0.0.0.0 --port $KUKSA_PORT --insecure || exit 1
fi
for i in $(seq 1 20); do nc -z localhost $KUKSA_PORT 2>/dev/null && break; sleep 0.5; done
echo "  KUKSA ready"

# 3. VEP Exporter
echo "[3/9] Starting vep_exporter..."
EXPORTER_CONTAINER="${CONTAINER_PREFIX}-exporter"
CONTAINERS+=("$EXPORTER_CONTAINER")
start_container "$EXPORTER_CONTAINER" $CONTAINER_PLATFORM $PULL_POLICY --network host \
    "$VEP_IMAGE" vep_exporter --broker $MQTT_BROKER --port $MQTT_PORT || exit 1

# 4. OTEL Probe
echo "[4/9] Starting vep_otel_probe..."
OTEL_CONTAINER="${CONTAINER_PREFIX}-otel"
CONTAINERS+=("$OTEL_CONTAINER")
start_container "$OTEL_CONTAINER" $CONTAINER_PLATFORM $PULL_POLICY --network host \
    "$VEP_IMAGE" vep_otel_probe --port $OTEL_GRPC_PORT || exit 1

# 5. Host Metrics
echo "[5/9] Starting vep_host_metrics..."
METRICS_CONTAINER="${CONTAINER_PREFIX}-metrics"
CONTAINERS+=("$METRICS_CONTAINER")
start_container "$METRICS_CONTAINER" $CONTAINER_PLATFORM $PULL_POLICY --network host \
    -v /proc:/host/proc:ro -v /sys:/host/sys:ro \
    -e HOST_PROC=/host/proc -e HOST_SYS=/host/sys \
    "$VEP_IMAGE" vep_host_metrics --endpoint localhost:$OTEL_GRPC_PORT --interval $HOST_METRICS_INTERVAL || exit 1

# 6. KUKSA-DDS Bridge
echo "[6/9] Starting kuksa_dds_bridge..."
KUKSA_BRIDGE="${CONTAINER_PREFIX}-kuksa-bridge"
CONTAINERS+=("$KUKSA_BRIDGE")
start_container "$KUKSA_BRIDGE" $CONTAINER_PLATFORM $PULL_POLICY --network host \
    "$VEP_IMAGE" kuksa_dds_bridge --kuksa localhost:$KUKSA_PORT --ready_timeout $KUKSA_TIMEOUT || exit 1

# 7. RT-DDS Bridge
echo "[7/9] Starting rt_dds_bridge..."
RT_BRIDGE="${CONTAINER_PREFIX}-rt-bridge"
CONTAINERS+=("$RT_BRIDGE")
start_container "$RT_BRIDGE" $CONTAINER_PLATFORM $PULL_POLICY --network host \
    "$VEP_IMAGE" rt_dds_bridge --transport loopback --loopback_delay_ms $RT_LOOPBACK_DELAY_MS || exit 1

# 8. CAN Probe
echo "[8/9] Starting vep_can_probe..."
CAN_PROBE="${CONTAINER_PREFIX}-can-probe"
CONTAINERS+=("$CAN_PROBE")
start_container "$CAN_PROBE" $CONTAINER_PLATFORM $PULL_POLICY --network host --cap-add NET_RAW \
    -v "$DBC_FILE:$CONTAINER_DBC_FILE:ro,z" \
    -v "$MAPPINGS_FILE:$CONTAINER_MAPPINGS_FILE:ro,z" \
    "$VEP_IMAGE" vep_can_probe \
        --config "$CONTAINER_MAPPINGS_FILE" \
        --dbc "$CONTAINER_DBC_FILE" \
        --interface "$AVTP_INTERFACE" \
        --transport avtp || exit 1

# 9. MQTT Receiver
echo "[9/9] Starting vep_mqtt_receiver..."
RECEIVER="${CONTAINER_PREFIX}-receiver"
CONTAINERS+=("$RECEIVER")

echo ""
echo "============================================================"
echo "Pipeline running! ($MODE_DESC)"
echo "============================================================"
echo ""
echo "To send CAN data:  sudo ./avtp-canplayer.sh avtp0 $CONFIG_DIR/candump.log"
echo ""
echo "Press Ctrl+C to stop."
echo "============================================================"
echo ""

# Run receiver in foreground
podman run --name "$RECEIVER" $CONTAINER_PLATFORM $PULL_POLICY --network host \
    "$VEP_IMAGE" vep_mqtt_receiver --broker $MQTT_BROKER --port $MQTT_PORT

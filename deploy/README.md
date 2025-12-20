# VEP Deployment Scripts

Containerized deployment scripts for Vehicle Edge Platform using podman/docker.

## Scripts

| Script | Description |
|--------|-------------|
| `01-otel-mqtt-chain.sh` | OTEL telemetry pipeline: host-metrics → otel-probe → exporter → mqtt |
| `02-avtp-vss-mqtt-chain.sh` | AVTP CAN pipeline: avtp-probe → exporter → mqtt |
| `03-full-pipeline.sh` | Full pipeline with KUKSA integration |
| `04-auto-pipeline.sh` | **Recommended** - Auto-architecture with Tesla config |
| `avtp-canplayer.sh` | Replay candump logs over AVTP (containerized) |
| `kuksa-logger.sh` | Log KUKSA databroker signals |
| `setup_avtp_loopback.sh` | Create avtp0/avtp1 veth pair for testing |

## Quick Start (04-auto-pipeline.sh)

The recommended deployment script auto-detects architecture and includes Tesla Model 3 config:

```bash
# Create AVTP loopback for testing
sudo ./setup_avtp_loopback.sh

# Start the full pipeline
sudo ./04-auto-pipeline.sh avtp1

# In another terminal, replay CAN data
sudo ./avtp-canplayer.sh avtp0 $(pwd)/config_tesla/candump.log
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONFIG_DIR` | `./config_tesla` | Config directory path |
| `DBC_FILE` | `$CONFIG_DIR/Model3CAN.dbc` | DBC file path |
| `MAPPINGS_FILE` | `$CONFIG_DIR/model3_mappings_dag.yaml` | VSS mappings path |
| `VSS_FILE` | `$CONFIG_DIR/vss-5.1-kuksa.json` | VSS schema path |
| `MQTT_PORT` | `1883` | MQTT broker port |
| `KUKSA_PORT` | `55555` | KUKSA databroker port |
| `OTEL_GRPC_PORT` | `4317` | OpenTelemetry gRPC port |

### Architecture Detection

- **Linux x86_64**: Uses `vep-autosd-runtime:ubi`, pulls images from registry
- **Linux ARM64**: Uses `vep-autosd-runtime:ubi-arm64`, uses `--pull=never` (airgapped)
- **macOS (Darwin)**: Uses x86_64 images via Rosetta

## Usage

### Dev Mode (x86_64)

Run locally for testing. Starts its own MQTT broker.

```bash
./deploy/01-otel-mqtt-chain.sh
```

### Target Mode (ARM64)

#### 1. Build ARM64 container (on dev machine)

```bash
cd docker/autosd
./build_cross.sh --ubi --slim
```

#### 2. Transfer to target

```bash
# Save and transfer VEP image
docker save vep-autosd-runtime:ubi-arm64 | ssh <target> "podman load"

# Also transfer KUKSA and Mosquitto ARM64 images
docker save ghcr.io/eclipse-kuksa/kuksa-databroker:0.6.0 | ssh <target> "podman load"
docker save arm64v8/eclipse-mosquitto:2 | ssh <target> "podman load"

# Sync deploy directory (includes config and scripts)
rsync -av deploy/ <target>:/opt/vep/
```

#### 3. Run on target (recommended: 04-auto-pipeline.sh)

```bash
cd /opt/vep

# Create AVTP loopback (if testing without real network)
sudo ./setup_avtp_loopback.sh

# Start the pipeline - auto-detects ARM64, uses --pull=never
sudo ./04-auto-pipeline.sh avtp1

# Send CAN data from another terminal
sudo ./avtp-canplayer.sh avtp0 $(pwd)/config_tesla/candump.log
```

#### Alternative: Legacy scripts with TARGET=1

```bash
# Uses onboard MQTT broker at localhost:1883
TARGET=1 ./01-otel-mqtt-chain.sh

# Or specify different MQTT broker
TARGET=1 MQTT_BROKER=192.168.1.100 ./01-otel-mqtt-chain.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET` | (unset) | Set to `1` for ARM64 target deployment |
| `MQTT_BROKER` | `localhost` | MQTT broker hostname/IP |
| `MQTT_PORT` | `1883` | MQTT broker port |

## Pipeline Overview

```
vep_host_metrics --> OTLP gRPC :4317 --> vep_otel_probe --> DDS --> vep_exporter --> MQTT --> vep_mqtt_logger
     |                                        |                          |                         |
  Linux metrics                         Converts to DDS              Compresses &              Displays
  (CPU, mem, disk)                      (gauges, counters)           batches                   (debug only)
```

## Resource Usage

The full pipeline uses approximately:
- CPU: ~1%
- Memory: ~15 MB total

| Container | CPU | Memory |
|-----------|-----|--------|
| mosquitto | 0.1% | ~1 MB |
| vep_exporter | 0.5% | ~3 MB |
| vep_otel_probe | 0.3% | ~5 MB |
| vep_host_metrics | 0.2% | ~3 MB |
| vep_mqtt_logger | 0.1% | ~2 MB |

# VEP Deployment Scripts

Containerized deployment scripts for Vehicle Edge Platform using podman.

## Scripts

| Script | Description |
|--------|-------------|
| `01-otel-mqtt-chain.sh` | OTEL telemetry pipeline: host-metrics -> otel-probe -> exporter -> mqtt |

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

#### 2. Transfer image to target

```bash
docker save vep-autosd-runtime:ubi-arm64 | ssh <target> "podman load"
```

#### 3. Copy deploy script to target

```bash
scp deploy/01-otel-mqtt-chain.sh <target>:~/
```

#### 4. Run on target

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
vep_host_metrics --> OTLP gRPC :4317 --> vep_otel_probe --> DDS --> vep_exporter --> MQTT --> vep_mqtt_receiver
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
| vep_mqtt_receiver | 0.1% | ~2 MB |

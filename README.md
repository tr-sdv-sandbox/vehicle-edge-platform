# Vehicle Edge Platform

A modular edge computing platform for vehicle data acquisition, transformation, and cloud ingestion.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            Vehicle Edge Platform                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐    │
│  │  VSS CAN     │  │  OTEL Probe  │◀─│ Host Metrics │  │  AVTP Probe   │    │
│  │   Probe      │  │  (gRPC :4317)│  │  Collector   │  │  (Ethernet)   │    │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘  └───────┬───────┘    │
│         │                 │                                    │            │
│         ▼                 ▼                                    ▼            │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                            DDS Bus                                   │   │
│  │                      (CycloneDDS + vdr_common)                       │   │
│  └───────┬─────────────────────┬─────────────────────┬──────────────────┘   │
│          │                     │                     │                      │
│          ▼                     ▼                     ▼                      │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐              │
│  │ VEP Exporter │      │  RT Bridge   │      │ Kuksa Bridge │  Bridges     │
│  │ (MQTT+zstd)  │      │  (loopback)  │      │    (gRPC)    │              │
│  └──────┬───────┘      └──────────────┘      └──────┬───────┘              │
│         │                                           │                       │
│         ▼                                           ▼                       │
│  ┌──────────────┐                           ┌──────────────┐                │
│  │   Mosquitto  │───▶ Cloud                 │    KUKSA     │◀── Apps       │
│  │    (MQTT)    │                           │  Databroker  │   (VSS API)   │
│  └──────────────┘                           └──────────────┘                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
        ▲                    ▲                    ▲
        │                    │                    │
   ┌────┴────┐         ┌─────┴─────┐        ┌────┴────┐
   │ CAN Bus │         │  OTel SDK │        │  AVTP   │
   │ (vcan0) │         │  (Apps)   │        │ Network │
   └─────────┘         └───────────┘        └─────────┘
```

## Components

| Component | Description |
|-----------|-------------|
| **libvss-types** | VSS (Vehicle Signal Specification) type definitions |
| **libvssdag** | CAN-to-VSS signal transformation using DAG mappings |
| **libkuksa-cpp** | C++ client for KUKSA.val databroker |
| **vep-dds** | DDS utilities and wrappers (vep_dds_common library) |
| **vep-schema** | DDS message types (IFEX → IDL generation) |
| **vep-core** | Probes, bridges, and exporters |

## Quick Start

### Prerequisites

Ubuntu 24.04:
```bash
./install_deps.u24.04.sh
```

### Setup

Clone all component repositories:
```bash
./setup.sh
```

### Build

Build all components:
```bash
./build-all.sh
```

### Run

Start the framework (all services):
```bash
./run_framework.sh
```

In another terminal, replay CAN data:
```bash
./run_canplayer.sh
```

View cloud backend output:
```bash
./run_aws_ingestion.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `setup.sh` | Clone all component repositories |
| `sync-all.sh` | Pull latest changes from all repos |
| `build-all.sh` | Build all components |
| `run_framework.sh` | Start all framework services (SocketCAN) |
| `run_framework_avtp.sh` | Start all framework services (IEEE 1722 AVTP) |
| `run_canplayer.sh` | Replay CAN data to vcan0 (SocketCAN) |
| `run_avtp_canplayer.sh` | Replay CAN data over IEEE 1722 AVTP |
| `run_aws_ingestion.sh` | Run MQTT receiver for testing |
| `run_kuksa_logger.sh` | Log KUKSA databroker values |
| `validate_mappings.sh` | Validate VSS signal mappings |

## Directory Structure

```
vehicle-edge-platform/
├── components/           # Component repositories (cloned by setup.sh)
│   ├── libvss-types/
│   ├── libvssdag/
│   ├── libkuksa-cpp/
│   ├── vep-dds/
│   ├── vep-schema/
│   └── vep-core/
├── config/               # Test configuration files
│   ├── candump.log       # Sample CAN data
│   ├── Model3CAN.dbc     # CAN database (signal definitions)
│   ├── model3_mappings_dag.yaml  # CAN-to-VSS mappings
│   └── vss-5.1-kuksa.json        # VSS specification
├── docker/               # Container builds
│   └── autosd/           # AutoSD/RHEL builds (CentOS, UBI, ARM64)
├── build/                # Build output (created by build-all.sh)
├── build-autosd/         # Docker build output
├── CMakeLists.txt        # Top-level CMake
└── *.sh                  # Utility scripts
```

## Key Binaries

After building:

| Binary | Location | Description |
|--------|----------|-------------|
| `vep_can_probe` | `build/vep-core/probes/vep_can_probe/` | CAN → VSS → DDS probe |
| `vep_otel_probe` | `build/vep-core/probes/vep_otel_probe/` | OTLP gRPC → DDS probe |
| `vep_avtp_probe` | `build/vep-core/probes/vep_avtp_probe/` | IEEE 1722 AVTP → DDS probe |
| `vep_exporter` | `build/vep-core/` | DDS → compressed MQTT exporter |
| `kuksa_dds_bridge` | `build/vep-core/` | KUKSA ↔ DDS bridge |
| `rt_dds_bridge` | `build/vep-core/` | RT transport ↔ DDS bridge |
| `vep_mqtt_receiver` | `build/vep-core/` | MQTT receiver/decoder |
| `vep_host_metrics` | `build/vep-core/tools/vep_host_metrics/` | Linux host metrics → OTLP |
| `avtp_canplayer` | `build/libvssdag/tools/avtp_canplayer/` | Replay candump logs over AVTP |
| `avtp_test_sender` | `build/libvssdag/tools/avtp_test_sender/` | Send test AVTP CAN frames |

## Data Flow

### CAN Telemetry
1. **CAN Ingestion**: `vep_can_probe` reads CAN frames from vcan0
2. **VSS Transformation**: libvssdag transforms CAN signals to VSS paths using DBC + YAML mappings
3. **DDS Publishing**: Signals published to DDS bus
4. **Export**: `vep_exporter` subscribes, batches, compresses (zstd), sends via MQTT
5. **Cloud**: `vep_mqtt_receiver` receives, decompresses, decodes protobuf

### Host/Application Metrics (OpenTelemetry)
1. **Metrics Collection**: `vep_host_metrics` collects Linux system metrics (CPU, memory, disk, network)
2. **OTLP Export**: Sends to `vep_otel_probe` via OTLP gRPC (port 4317)
3. **DDS Bridge**: `vep_otel_probe` converts OTEL metrics to DDS messages
4. **Cloud Export**: `vep_exporter` batches metrics and sends via MQTT
5. **Display**: `vep_mqtt_receiver` shows metrics with service labels (`service=vep_host_metrics@hostname`)

## CAN Transport Options

`vep_can_probe` supports two CAN transports:

| Transport | Interface | Use Case |
|-----------|-----------|----------|
| `socketcan` | vcan0, can0 | Standard Linux CAN interfaces |
| `avtp` | eth0, enp0s3 | IEEE 1722 AVTP over Ethernet |

```bash
# SocketCAN (default)
./vep_can_probe --config mappings.yaml --interface vcan0 --dbc model3.dbc

# AVTP over Ethernet (for targets without vcan)
./vep_can_probe --config mappings.yaml --interface eth0 --dbc model3.dbc --transport avtp
```

### Permissions

**AVTP Transport** - Requires raw Ethernet sockets:

| Environment | Command |
|-------------|---------|
| Standalone (root) | `sudo ./vep_can_probe --transport avtp ...` |
| Standalone (capability) | `sudo setcap cap_net_raw+ep ./vep_can_probe` |
| Container | `docker run --cap-add NET_RAW --network host ...` |
| Container (privileged) | `docker run --privileged --network host ...` |

**SocketCAN** - Requires vcan kernel module on host:
```bash
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0
```

Containers need `--network host` to access host's vcan interfaces.

### AVTP Tools

libvssdag includes tools for testing and replaying CAN data over IEEE 1722 AVTP:

**avtp_canplayer** - Replay candump log files over AVTP (like `canplayer` but over Ethernet):
```bash
# Basic replay with timestamps
./run_avtp_canplayer.sh eth0 config/candump.log

# Or directly:
sudo ./build/libvssdag/tools/avtp_canplayer/avtp_canplayer \
    -I config/candump.log --interface eth0

# Options:
#   --speed 2.0       Playback at 2x speed
#   --loop            Loop continuously
#   --no-timestamps   Send as fast as possible
#   --interval 10     Fixed 10ms between frames
```

**avtp_test_sender** - Send individual test CAN frames:
```bash
sudo ./build/libvssdag/tools/avtp_test_sender/avtp_test_sender \
    --interface eth0 --can-id 0x123 --data "01 02 03 04"
```

Supports both standard (11-bit) and extended (29-bit J1939) CAN IDs.

## Docker Builds (AutoSD/RHEL)

For containerized deployments targeting CentOS Stream 9 / RHEL-based automotive OS:

```bash
cd docker/autosd

# Build development container (~4.8GB, includes all build tools)
./build_container.sh

# Build VEP binaries inside container (output: build-autosd/)
./build_autosd.sh

# Create minimal runtime containers
./build_runtime.sh --slim      # CentOS Stream 9 (~251MB)
./build_runtime_ubi.sh --slim  # UBI minimal (~148MB)

# ARM64 cross-compilation (QEMU-based, for NXP i.MX, etc.)
./build_cross.sh --ubi --slim  # Creates vep-autosd-runtime:ubi-arm64 (~156MB)
```

| Image | Size | Description |
|-------|------|-------------|
| `autosd-vep` | ~4.8GB | Full build environment |
| `vep-autosd-runtime` | ~251MB | CentOS Stream 9 runtime |
| `vep-autosd-runtime:ubi` | ~148MB | UBI minimal runtime |
| `vep-autosd-runtime:ubi-arm64` | ~156MB | ARM64 UBI runtime |

Run the runtime container:
```bash
docker run -it --privileged --network host vep-autosd-runtime:ubi
```

See `docker/autosd/README.md` for detailed documentation.

## Configuration

### CAN-to-VSS Mappings

The YAML mapping file references DBC signal names and maps them to VSS paths:

```yaml
mappings:
  - signal: Vehicle.Speed
    source:
      type: dbc
      name: DI_vehicleSpeed      # Signal name from DBC file
    datatype: float
    min_interval_ms: 100         # Rate limit to 10Hz
    max_interval_ms: 1000        # Heartbeat every 1s
    change_threshold: 0.5        # Deadband filter
    transform:
      code: "lowpass(x, 0.3)"    # Lua transform
```

The DBC file (`Model3CAN.dbc`) defines the CAN signal structure (message IDs, bit positions, scaling).

Validate mappings against VSS spec:
```bash
./validate_mappings.sh
```

## License

See individual component repositories for license information.

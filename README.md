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
| **vep-dds** | DDS utilities and wrappers (vdr_common library) |
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
| `run_framework.sh` | Start all framework services |
| `run_canplayer.sh` | Replay CAN data to vcan0 |
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
│   └── vep-core/
├── config/               # Test configuration files
│   ├── candump.log       # Sample CAN data
│   ├── Model3CAN.dbc     # CAN database (signal definitions)
│   ├── model3_mappings_dag.yaml  # CAN-to-VSS mappings
│   └── vss-5.1-kuksa.json        # VSS specification
├── build/                # Build output (created by build-all.sh)
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

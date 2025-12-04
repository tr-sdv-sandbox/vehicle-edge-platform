# Vehicle Edge Platform

A modular edge computing platform for vehicle data acquisition, transformation, and cloud ingestion.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Vehicle Edge Platform                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                  │
│  │  VSS CAN     │  │  OTEL Probe  │  │  AVTP Probe  │   Probes         │
│  │   Probe      │  │  (gRPC in)   │  │  (Ethernet)  │                  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘                  │
│         │                 │                 │                           │
│         ▼                 ▼                 ▼                           │
│  ┌─────────────────────────────────────────────────────┐               │
│  │                      DDS Bus                        │               │
│  │                (CycloneDDS + vdr_common)            │               │
│  └───────┬─────────────────┬─────────────────┬─────────┘               │
│          │                 │                 │                          │
│          ▼                 ▼                 ▼                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                  │
│  │ VDR Exporter │  │  RT Bridge   │  │ Kuksa Bridge │   Bridges        │
│  │ (MQTT+zstd)  │  │  (loopback)  │  │    (gRPC)    │                  │
│  └──────┬───────┘  └──────────────┘  └──────┬───────┘                  │
│         │                                   │                           │
│         ▼                                   ▼                           │
│  ┌──────────────┐                   ┌──────────────┐                   │
│  │   Mosquitto  │───▶ Cloud         │    KUKSA     │◀── 3rd Party Apps │
│  │    (MQTT)    │                   │  Databroker  │    (VSS API)      │
│  └──────────────┘                   └──────────────┘                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
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
| `run_aws_ingestion.sh` | Run cloud backend simulator |
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
| `vdr_vss_can_probe` | `build/vep-core/probes/vss_can/` | CAN → VSS → DDS probe |
| `vdr_otel_probe` | `build/vep-core/probes/otel/` | OTLP gRPC → DDS probe |
| `vdr_avtp_probe` | `build/vep-core/probes/avtp/` | IEEE 1722 AVTP → DDS probe |
| `vdr_exporter` | `build/vep-core/` | DDS → compressed MQTT exporter |
| `kuksa_dds_bridge` | `build/vep-core/` | KUKSA ↔ DDS bridge |
| `rt_dds_bridge` | `build/vep-core/` | RT transport ↔ DDS bridge |
| `cloud_backend_sim` | `build/vep-core/` | MQTT receiver/decoder |

## Data Flow

1. **CAN Ingestion**: `vdr_vss_can_probe` reads CAN frames from vcan0
2. **VSS Transformation**: libvssdag transforms CAN signals to VSS paths using DBC + YAML mappings
3. **DDS Publishing**: Signals published to DDS bus
4. **Export**: `vdr_exporter` subscribes, batches, compresses (zstd), sends via MQTT
5. **Cloud**: `cloud_backend_sim` receives, decompresses, decodes protobuf

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

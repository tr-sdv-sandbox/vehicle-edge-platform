# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Vehicle Edge Platform is a modular edge computing platform for vehicle data acquisition, transformation, and cloud ingestion. It uses CycloneDDS as the central message bus with specialized probes (CAN, OTEL, AVTP), bridges (KUKSA, RT transport), and exporters (MQTT with zstd compression).

## Build Commands

```bash
# One-time setup (Ubuntu 24.04)
./install_deps_u24.04.sh
./setup.sh                    # Clone component repositories

# Build all components
./build-all.sh [Release|Debug] [parallel_jobs]

# Run tests
cd build && ctest --output-on-failure

# Run single component tests
cd build/<component> && ctest --output-on-failure
```

## Virtual CAN Setup

Required for testing CAN-based probes:
```bash
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0
```

## Running the Framework

```bash
./run_framework.sh            # Start all services (KUKSA, probes, bridges, exporter)
./run_canplayer.sh            # Replay CAN data to vcan0 (in another terminal)
./run_aws_ingestion.sh        # View MQTT receiver output
./run_kuksa_logger.sh         # Log KUKSA databroker values
./validate_mappings.sh        # Validate VSS signal mappings against spec
```

## Architecture

**Sensor Flow:** CAN/OTEL/AVTP → Probes → DDS Bus → Bridges/Exporters → MQTT/KUKSA

**Actuator Flow:** App → KUKSA set() → kuksa_dds_bridge → DDS target → rt_dds_bridge → RT hardware
                                    ← kuksa_dds_bridge ← DDS actual ←

**Components (build order = dependency order):**
1. **libvss-types** - VSS type definitions with quality indicators (VALID/INVALID/NOT_AVAILABLE)
2. **libvssdag** - CAN→VSS transformation using DAG + embedded Lua transforms
3. **libkuksa-cpp** - Type-safe C++ client for KUKSA.val databroker (gRPC)
4. **vep-dds** - DDS utilities (vep_dds_common library), RAII wrappers around CycloneDDS C API
5. **vep-schema** - IDL message definitions in COVESA IFEX format (generates IDL for DDS)
6. **vep-core** - Probes, bridges, and exporters
7. **covesa-ifex-core** - (optional) COVESA IFEX vehicle orchestration services

**DDS Topics:** `rt/vss/signals` (sensors), `rt/vss/actuators/target`, `rt/vss/actuators/actual`

**Key Binaries (in build/):**
- `vep-core/probes/vep_can_probe/vep_can_probe` - CAN → VSS → DDS
- `vep-core/probes/vep_otel_probe/vep_otel_probe` - OTLP gRPC → DDS
- `vep-core/probes/vep_avtp_probe/vep_avtp_probe` - IEEE 1722 AVTP → DDS
- `vep-core/vep_exporter` - DDS → compressed MQTT
- `vep-core/kuksa_dds_bridge` - KUKSA ↔ DDS bidirectional bridge
- `vep-core/vep_mqtt_receiver` - MQTT receiver/decoder for testing

**Ports:** KUKSA Databroker (gRPC) 61234, Mosquitto (MQTT) 1883, DDS multicast RTPS

## Configuration Files

- `config/Model3CAN.dbc` - CAN signal definitions (message IDs, bit positions, scaling)
- `config/model3_mappings_dag.yaml` - CAN→VSS mappings with Lua transforms, rate limits, deadbands
- `config/vss-5.1-kuksa.json` - VSS 5.1 specification
- `config/candump.log` - Sample CAN data for replay testing

## Code Conventions

- **Languages:** C++17 (primary), Lua (embedded transforms), Protobuf (wire format)
- **Namespaces:** `vss::types::`, `vssdag::`, `kuksa::`, `dds::`, `vep::` (IDL types), `utils::`
- **Naming:** snake_case functions, trailing underscore members (`nodes_`), UPPER_CASE constants
- **Logging:** glog (`LOG(INFO)`, `LOG(ERROR)`, `CHECK`, `DCHECK`)
- **Testing:** Google Test in `tests/` directories
- **Real-time:** Lock-free queues (moodycamel::concurrentqueue) in hot paths
- **Smart pointers:** Use throughout; raw pointers only for DAG traversal within scope
- **DDS strings:** C-style strings required; keep buffers valid until after `write()` completes

## Threading Model (libkuksa-cpp)

- Resolver: synchronous, thread-safe, use during initialization
- Client sync ops (get/set): work from any thread
- Client async callbacks: run on gRPC threads - keep fast (<1ms), queue heavy work
- Never call `publish()` from within subscription/actuator callbacks (gRPC deadlock)

## Component Documentation

Each component in `components/` has its own `CLAUDE.md` with component-specific guidance, plus `README.md` for detailed API documentation. Key files:
- `components/libvssdag/README.md` - Comprehensive Lua transform API reference
- `components/libkuksa-cpp/USAGE.md` - Complete client library API reference
- `components/vep-core/ARCHITECTURE.md` - System architecture and data flows
- `components/vep-dds/CLAUDE.md` - DDS wrapper patterns, IDL topic naming, vep_dds_common library
- `components/vep-schema/README.md` - Message types, topic naming, QoS recommendations

## CMake Options

```bash
# Top-level options
-DVEP_BUILD_TESTS=ON          # Build tests (default: ON)
-DVEP_BUILD_EXAMPLES=ON       # Build examples (default: ON)
-DCMAKE_BUILD_TYPE=Release    # Release or Debug
```

## Docker Builds (AutoSD/RHEL)

Container builds for CentOS Stream 9 / RHEL-based automotive OS (AutoSD):

```bash
cd docker/autosd

# Build development container (one-time, ~4.8GB)
./build_container.sh

# Build VEP inside container
./build_autosd.sh

# Create runtime containers
./build_runtime.sh --slim      # CentOS Stream 9 (~251MB)
./build_runtime_ubi.sh --slim  # UBI minimal (~148MB, smallest)

# ARM64 cross-compilation (for NXP i.MX, etc.)
./build_cross.sh --ubi --slim  # Creates vep-autosd-runtime:ubi-arm64 (~156MB)
```

See `docker/autosd/README.md` for detailed documentation.

## IDL Message Types

DDS message definitions are generated from IFEX schemas in `components/vep-schema/`. Key types (in `vep::` namespace):
- `vep::VssSignal` - VSS signal with quality and typed value
- `vep::Event` - Vehicle events with severity
- `vep::OtelGauge`, `vep::OtelCounter`, `vep::OtelHistogram` - Prometheus-style metrics
- `vep::AvtpCanFrame` - IEEE 1722 CAN-over-Ethernet frames
- `vep::OtelLogEntry` - Structured log entries

All messages include a common `vep::Header` with `source_id`, `timestamp_ns`, `seq_num`, `correlation_id`.

To regenerate IDL from IFEX: `cd components/vep-schema && ./generate-all.sh`

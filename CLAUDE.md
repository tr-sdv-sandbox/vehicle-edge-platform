# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Vehicle Edge Platform is a modular edge computing platform for vehicle data acquisition, transformation, and cloud ingestion. It uses CycloneDDS as the central message bus with specialized probes (CAN, OTEL, AVTP), bridges (KUKSA, RT transport), and exporters (MQTT with zstd compression).

**Key Dependencies:** CycloneDDS, gRPC/Protobuf, Lua 5.4, Open1722 (IEEE 1722 AVTP), vsomeip3 (SOME/IP), libmosquitto, zstd

## Build Commands

```bash
# One-time setup (Ubuntu 24.04)
./install_deps_u24.04.sh
./setup.sh                    # Clone component repositories

# Build all components
./build-all.sh [Release|Debug] [parallel_jobs] [--strip]

# Run all tests
cd build && ctest --output-on-failure

# Run single component tests
cd build/<component> && ctest --output-on-failure

# Run specific test by name pattern
cd build && ctest -R "state_machine" --output-on-failure

# Run single Google Test case
./build/libkuksa-cpp/tests/state_machine_tests --gtest_filter="StateMachineTest.BasicTransition"

# Sync all component repos (pull latest)
./sync-all.sh
```

## Virtual CAN Setup

Required for testing CAN-based probes:
```bash
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0
```

## AVTP Loopback Setup

For AVTP testing without physical network, create a virtual Ethernet pair:
```bash
./scripts/setup_avtp_loopback.sh   # Creates avtp0/avtp1 veth pair
# Use avtp0 for sender, avtp1 for receiver (or vice versa)
```

## CAN Transport Options

vep_can_probe supports two CAN transports:

| Transport | Interface | Use Case |
|-----------|-----------|----------|
| `socketcan` | vcan0, can0 | Standard Linux CAN interfaces |
| `avtp` | eth0, enp0s3 | IEEE 1722 AVTP over Ethernet (for targets without vcan) |

```bash
# SocketCAN (default)
./vep_can_probe --config mappings.yaml --interface vcan0 --dbc model3.dbc

# AVTP over Ethernet
./vep_can_probe --config mappings.yaml --interface eth0 --dbc model3.dbc --transport avtp
```

### Permissions

**AVTP Transport (IEEE 1722)** - Requires raw Ethernet sockets:

| Environment | Command |
|-------------|---------|
| Standalone (root) | `sudo ./vep_can_probe --transport avtp ...` |
| Standalone (capability) | `sudo setcap cap_net_raw+ep ./vep_can_probe` |
| Container | `docker run --cap-add NET_RAW --network host ...` |
| Container (privileged) | `docker run --privileged --network host ...` |

**SocketCAN** - Requires vcan setup on host:
- Containers need `--network host` to access host's vcan interfaces
- No special capabilities required beyond vcan kernel module

## Running the Framework

**Native scripts** (in `scripts/`) run binaries from `build/`:

```bash
./scripts/run_framework.sh         # Start all services (KUKSA, probes, bridges, exporter) - SocketCAN
./scripts/run_framework_avtp.sh    # Start all services using IEEE 1722 AVTP transport
./scripts/run_canplayer.sh         # Replay CAN data to vcan0 (SocketCAN)
./scripts/run_avtp_canplayer.sh    # Replay CAN data over IEEE 1722 AVTP
./scripts/run_aws_ingestion.sh     # View MQTT receiver output
./scripts/run_kuksa_logger.sh      # Log KUKSA databroker values
./scripts/validate_mappings.sh     # Validate VSS signal mappings against spec
./scripts/setup_avtp_loopback.sh   # Creates avtp0/avtp1 veth pair for AVTP testing
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
- `vep-core/rt_dds_bridge` - DDS ↔ RT transport (loopback for testing)
- `vep-core/vep_mqtt_logger` - MQTT logger/decoder for testing
- `vep-core/tools/vep_host_metrics/vep_host_metrics` - Linux metrics → OTLP
- `libvssdag/tools/avtp_canplayer/avtp_canplayer` - Replay candump over AVTP
- `libvssdag/tools/avtp_test_sender/avtp_test_sender` - Send test AVTP CAN frames

**Ports:** KUKSA (gRPC) 61234, Mosquitto (MQTT) 1883, OTLP (gRPC) 4317, DDS multicast RTPS

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

## Debugging

```bash
# Verbose logging (glog)
GLOG_logtostderr=1 GLOG_v=1 ./vep_can_probe ...

# DDS debugging - see all DDS traffic
export CYCLONEDDS_URI='<CycloneDDS><Domain><Tracing><Verbosity>finest</Verbosity></Tracing></Domain></CycloneDDS>'

# Monitor DDS topics (requires cyclonedds-tools)
ddsperf pub topic rt/vss/signals   # Publish test
ddsperf sub topic rt/vss/signals   # Subscribe test

# AVTP packet capture
sudo tcpdump -i eth0 -w avtp.pcap 'ether proto 0x22f0'
```

## Component Documentation

Each component in `components/` has its own `CLAUDE.md` with component-specific guidance, plus `README.md` for detailed API documentation. Key files:
- `components/libvssdag/README.md` - Comprehensive Lua transform API reference
- `components/libkuksa-cpp/USAGE.md` - Complete client library API reference
- `components/vep-core/ARCHITECTURE.md` - System architecture and data flows
- `components/vep-dds/CLAUDE.md` - DDS wrapper patterns, IDL topic naming, vep_dds_common library
- `components/vep-schema/README.md` - Message types, topic naming, QoS recommendations

**When working on a specific component**, read its `CLAUDE.md` first for component-specific build commands, architecture, and code conventions.

## CMake Options

```bash
# Top-level options
-DVEP_BUILD_TESTS=ON          # Build tests (default: ON)
-DVEP_BUILD_EXAMPLES=ON       # Build examples (default: ON)
-DCMAKE_BUILD_TYPE=Release    # Release or Debug
```

## Integration Tests

Some integration tests auto-start Docker containers:
- `KuksaTestFixture` - Starts KUKSA databroker (libkuksa-cpp tests)
- `MqttTestFixture` - Starts Mosquitto broker (vep-core backend_transport tests)

To use external brokers instead of Docker:
```bash
export KUKSA_ADDRESS=host:port   # Skip KUKSA Docker container
export MQTT_HOST=host:port       # Skip Mosquitto Docker container
```

## Extending the Platform

**Adding a new probe:**
1. Create directory under `components/vep-core/probes/`
2. Add `main.cpp` with gflags CLI parsing
3. Use vep_dds_common for DDS publishing
4. Add to `probes/CMakeLists.txt`

**Adding a new DDS message type:**
1. Define in `components/vep-schema/ifex/`
2. Regenerate: `cd components/vep-schema && ./generate-all.sh`
3. Add encoder in `vep-core/bridges/exporter_common/src/wire_encoder.cpp`
4. Add decoder in `vep-core/bridges/exporter_common/src/wire_decoder.cpp`
5. Add to subscriber in `vep-core/bridges/exporter_common/src/subscriber.cpp`

**Modifying wire protocol:**
1. Edit `components/vep-core/proto/transfer.proto`
2. Rebuild (CMake regenerates automatically)
3. Update wire_encoder.cpp and wire_decoder.cpp

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

## Containerized Deployment (deploy/)

**Containerized scripts** (in `deploy/`) run via podman/docker, deployable to targets without build environment:

```bash
cd deploy

# OTEL pipeline only (host-metrics → otel-probe → exporter → mqtt)
./01-otel-mqtt-chain.sh

# AVTP CAN pipeline (avtp-probe → exporter → mqtt)
./02-avtp-vss-mqtt-chain.sh

# Full pipeline with KUKSA integration
./03-full-pipeline.sh

# Auto-architecture pipeline (recommended for production)
sudo ./04-auto-pipeline.sh avtp1         # Auto-detects x86_64/ARM64, uses config_tesla/

# Utilities
./avtp-canplayer.sh eth0 candump.log    # Replay CAN over AVTP (containerized)
./kuksa-logger.sh                        # Log KUKSA signals (containerized)
./setup_avtp_loopback.sh                 # Create veth pair for AVTP testing

# ARM64 target deployment
TARGET=1 ./01-otel-mqtt-chain.sh         # Uses ARM64 container image
```

**04-auto-pipeline.sh** features:
- Auto-detects architecture (x86_64, ARM64, Darwin)
- Dev machines sync VEP from docker, pull public images
- Targets (Linux ARM64) use `--pull=never` for airgapped operation
- Uses Tesla config from `deploy/config_tesla/` by default
- Configurable via env vars: `CONFIG_DIR`, `DBC_FILE`, `MAPPINGS_FILE`, `KUKSA_PORT`, etc.

## IDL Message Types

DDS message definitions are generated from IFEX schemas in `components/vep-schema/`. Key types (in `vep::` namespace):
- `vep::VssSignal` - VSS signal with quality and typed value
- `vep::Event` - Vehicle events with severity
- `vep::OtelGauge`, `vep::OtelCounter`, `vep::OtelHistogram` - Prometheus-style metrics
- `vep::AvtpCanFrame` - IEEE 1722 CAN-over-Ethernet frames
- `vep::OtelLogEntry` - Structured log entries

All messages include a common `vep::Header` with `source_id`, `timestamp_ns`, `seq_num`, `correlation_id`.

To regenerate IDL from IFEX: `cd components/vep-schema && ./generate-all.sh`

## Wire Protocol

The exporter uses a bandwidth-optimized protobuf format (`transfer.proto`):
- Delta timestamps (base timestamp + per-signal deltas in microseconds)
- Batched signals (multiple signals per message)
- Zstd compression (60-80% bandwidth reduction)

See `components/vep-core/proto/transfer.proto` for message definitions.

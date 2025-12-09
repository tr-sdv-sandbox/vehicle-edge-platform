# AutoSD Docker Build Environment

Build and runtime containers for Vehicle Edge Platform targeting AutoSD (CentOS Stream 9 / RHEL-based automotive OS).

## Quick Start

```bash
# Build the development container (one-time, ~4.8GB)
./build_container.sh

# Build VEP inside the container
./build_autosd.sh

# Create runtime container (~251MB CentOS, ~148MB UBI)
./build_runtime.sh --slim
./build_runtime_ubi.sh --slim
```

## Images

| Image | Size | Description |
|-------|------|-------------|
| `autosd-vep` | ~4.8GB | Full build environment with all tools and dependencies |
| `vep-autosd-runtime` | ~251MB | CentOS Stream 9 runtime with VEP binaries |
| `vep-autosd-runtime:ubi` | ~148MB | UBI minimal runtime (smallest RHEL-compatible) |

## Scripts

### build_container.sh
Builds the development container with all build tools and dependencies.

```bash
./build_container.sh [--no-cache]
```

### build_autosd.sh
Runs the VEP build inside the container, outputting to `build-autosd/` in the project root.

```bash
./build_autosd.sh [--no-cache] [--clean]
```

### build_runtime.sh
Creates a minimal runtime container from the build container.

```bash
./build_runtime.sh [--no-cache] [--tag TAG] [--slim]

Options:
  --no-cache    Don't use Docker cache
  --tag TAG     Tag for runtime image (default: vep-autosd-runtime)
  --slim        Flatten image to reduce size (~250MB vs ~480MB)
```

### build_runtime_ubi.sh
Creates a UBI minimal-based runtime container (smallest RHEL-compatible option).

```bash
./build_runtime_ubi.sh [--no-cache] [--tag TAG] [--slim]
```

## Cross-Compilation (ARM64/aarch64)

For building ARM64 images (e.g., for NXP i.MX targets), use the `build_cross.sh` script.

### Prerequisites

1. **Register QEMU for multi-arch builds** (one-time setup, requires privileged):
   ```bash
   docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
   ```

2. **Install Docker buildx** (if not already available):
   ```bash
   # Check if buildx is available
   docker buildx version

   # If not, install it (Ubuntu 24.04)
   sudo apt-get install docker-buildx
   ```

### Building ARM64 Images

Use the `build_cross.sh` script which handles all the complexity:

```bash
# Build ARM64 build container only
./build_cross.sh

# Build ARM64 UBI runtime (recommended - smallest)
./build_cross.sh --ubi --slim

# Build ARM64 CentOS runtime
./build_cross.sh --runtime --slim

# Build for different platform (e.g., ARMv7)
./build_cross.sh --platform linux/arm/v7 --ubi --slim
```

The script automatically:
- Sets up QEMU if needed
- Creates a buildx builder with proper configuration
- Builds the base container (`autosd-vep:arm64`)
- For runtime builds: starts a temporary local registry to share images with buildx
- Optionally flattens the image with `--slim`

Note: QEMU emulation is significantly slower than native builds. Expect 10-30x longer build times.

### Verifying ARM64 Images

```bash
# Check architecture
docker run --rm vep-autosd-runtime:ubi-arm64 uname -m
# Should output: aarch64

# Test binaries (runs under QEMU)
docker run --rm vep-autosd-runtime:ubi-arm64 vep_can_probe --help
```

### Manual Cross-Build (Advanced)

If you need more control, you can build manually:

```bash
# Build ARM64 build container
docker buildx build --platform linux/arm64 \
    --network host \
    -t autosd-vep:arm64 \
    -f Dockerfile.autosd \
    --load \
    ../..
```

For runtime builds, the multi-stage Dockerfiles require the base image to be accessible to buildx. The `build_cross.sh` script handles this by using a temporary local registry.

## Running the Runtime Container

```bash
# Interactive shell
docker run -it --privileged --network host vep-autosd-runtime

# With CAN interface access
docker run -it --privileged --network host \
    -v /dev:/dev \
    vep-autosd-runtime

# With custom config
docker run -it --privileged --network host \
    -v /path/to/config:/etc/vep/config:ro \
    vep-autosd-runtime
```

## Available Binaries

| Binary | Description |
|--------|-------------|
| `vep_can_probe` | CAN → VSS → DDS probe |
| `vep_otel_probe` | OTLP gRPC → DDS probe |
| `vep_exporter` | DDS → compressed MQTT exporter |
| `vep_mqtt_receiver` | MQTT receiver/decoder (testing) |
| `kuksa_dds_bridge` | KUKSA ↔ DDS bidirectional bridge |
| `rt_dds_bridge` | DDS ↔ RT transport bridge |
| `vep_host_metrics` | Host metrics → OTLP collector |

## Dockerfile Variants

### Dockerfile.autosd
Full build environment based on CentOS Stream 9 with:
- GCC 11, CMake, pkg-config
- gRPC, Protobuf, Abseil (built from source as shared libs)
- CycloneDDS, glog, gflags
- Lua 5.4, yaml-cpp, nlohmann-json
- dbcppp (CAN DBC parser)

### Dockerfile.runtime
Multi-stage build producing minimal CentOS Stream 9 runtime:
- Stage 1: Build VEP using `autosd-vep`
- Stage 2: Copy only runtime libraries and binaries to clean CentOS base

### Dockerfile.runtime.ubi
Same as above but using UBI minimal base for smallest footprint:
- Based on `registry.access.redhat.com/ubi9/ubi-minimal`
- Uses microdnf instead of dnf
- Copies additional libs (yaml-cpp, mosquitto, c-ares) not in UBI repos

## Troubleshooting

### "autosd-vep not found"
Build the base container first:
```bash
./build_container.sh
```

### Permission denied on build-autosd/
The build script runs as your user. If you see permission issues:
```bash
sudo chown -R $(id -u):$(id -g) ../../build-autosd
```

### Missing shared libraries at runtime
Check which libs are missing:
```bash
docker run --rm vep-autosd-runtime ldd /usr/local/bin/vep_exporter
```
Add missing libs to the Dockerfile.runtime COPY/mv commands.

### QEMU: "exec format error"
Re-register QEMU handlers:
```bash
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

#!/bin/bash
# Run KUKSA logger to display databroker values

set -ef

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

"$BUILD_DIR/libkuksa-cpp/utils/kuksa_logger" --address=localhost:61234

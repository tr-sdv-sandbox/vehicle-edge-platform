#!/bin/bash
# Run KUKSA logger to display databroker values

set -ef

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

"$BUILD_DIR/libkuksa-cpp/utils/kuksa_logger" --address=localhost:61234

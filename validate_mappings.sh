#!/bin/bash
# Validate YAML signal mappings against VSS specification
#
# Usage: ./validate_mappings.sh [options]
#
# Options are passed through to the validation tool:
#   --verbose, -v    Show all valid signals
#   --strict         Treat custom signals as errors
#   --json           Output results as JSON

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
CONFIG_DIR="$SCRIPT_DIR/config"

YAML_FILE="$CONFIG_DIR/model3_mappings_dag.yaml"
VSS_FILE="$CONFIG_DIR/vss-5.1-kuksa.json"

VALIDATOR="$SCRIPT_DIR/components/libvssdag/tools/validate_mappings/vssdag_validate_mappings.py"

if [ ! -f "$VALIDATOR" ]; then
    echo "Error: vssdag_validate_mappings.py not found at $VALIDATOR"
    exit 1
fi

python3 "$VALIDATOR" --yaml "$YAML_FILE" --vss "$VSS_FILE" "$@"

#!/bin/bash
# Vehicle Edge Platform - Workspace Setup
# Clones all component repositories into the components/ directory
#
# Usage:
#   ./setup.sh          # Use SSH URLs (default)
#   ./setup.sh --https  # Use HTTPS URLs (for containers without SSH keys)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENTS_DIR="$SCRIPT_DIR/components"

# Default to SSH, use HTTPS if --https flag or SSH is unavailable
if [[ "$1" == "--https" ]] || ! ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    GIT_ORG="https://github.com/tr-sdv-sandbox"
    echo "Using HTTPS URLs for git clone"
else
    GIT_ORG="git@github.com:tr-sdv-sandbox"
    echo "Using SSH URLs for git clone"
fi

# Component repositories
REPOS=(
    "libvss-types"
    "libvssdag"
    "libkuksa-cpp"
    "vep-dds"
    "vep-core"
    "vep-schema"
)

echo "=== Vehicle Edge Platform Setup ==="
echo "Components directory: $COMPONENTS_DIR"
echo ""

mkdir -p "$COMPONENTS_DIR"
cd "$COMPONENTS_DIR"

for repo in "${REPOS[@]}"; do
    if [ -d "$repo" ]; then
        echo "[$repo] Already exists, skipping clone"
    else
        echo "[$repo] Cloning..."
        git clone "$GIT_ORG/$repo.git"
    fi
done

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run ./sync-all.sh to pull latest changes"
echo "  2. Run ./build-all.sh to build everything"
echo "  3. Run ./run-demo.sh to start the demo pipeline"
echo ""

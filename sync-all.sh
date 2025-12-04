#!/bin/bash
# Vehicle Edge Platform - Sync All Repositories
# Pulls latest changes from all component repositories

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENTS_DIR="$SCRIPT_DIR/components"

REPOS=(
    "libvss-types"
    "libvssdag"
    "libkuksa-cpp"
    "vep-dds"
    "vep-core"
)

echo "=== Syncing All Repositories ==="
echo ""

for repo in "${REPOS[@]}"; do
    if [ -d "$COMPONENTS_DIR/$repo" ]; then
        echo "[$repo] Pulling latest..."
        cd "$COMPONENTS_DIR/$repo"
        git fetch origin

        # Check if there are local changes
        if ! git diff --quiet HEAD; then
            echo "  WARNING: Local changes detected, skipping pull"
            git status --short
        else
            git pull --ff-only origin main 2>/dev/null || \
            git pull --ff-only origin master 2>/dev/null || \
            echo "  WARNING: Could not fast-forward, manual merge may be needed"
        fi
        echo ""
    else
        echo "[$repo] Not found, run ./setup.sh first"
    fi
done

echo "=== Sync Complete ==="

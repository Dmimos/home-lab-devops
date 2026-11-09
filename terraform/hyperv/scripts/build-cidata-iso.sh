#!/bin/bash
set -e

# The output path is passed as the first argument from Terraform
OUTPUT_ISO="$1"
if [ -z "$OUTPUT_ISO" ]; then
    echo "Error: No output path provided."
    exit 1
fi

CLOUD_INIT_DIR="$(dirname "$0")/../cloud-init"

# Check for genisoimage
if ! command -v genisoimage &> /dev/null; then
    echo "genisoimage not found. Installing..."
    sudo apt-get update && sudo apt-get install -y genisoimage
fi

# Ensure the target directory exists (convert Linux path to Windows path for WSL)
WIN_OUTPUT_DIR=$(dirname "$OUTPUT_ISO")
# Create directory if it doesn't exist (WSL can access Windows paths via /mnt/c/...)
if [ ! -d "$WIN_OUTPUT_DIR" ]; then
    mkdir -p "$WIN_OUTPUT_DIR"
fi

echo "Building ISO from rendered files..."
genisoimage -output "$OUTPUT_ISO" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/rendered-user-data.yaml" "$CLOUD_INIT_DIR/meta-data.yaml"

echo "ISO successfully built at: $OUTPUT_ISO"
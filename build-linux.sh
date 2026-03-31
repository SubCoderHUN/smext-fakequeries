#!/bin/bash
# Build Linux .so extension using Docker
# Works on Windows (Git Bash/WSL), Linux, and macOS
#
# Usage:
#   ./build-linux.sh          - Build with defaults (CS:GO SDK)
#   ./build-linux.sh tf2      - Build with specific SDK

set -e

SDK="${1:-csgo}"

echo "============================================"
echo " Building fakequeries Linux .so extension"
echo " SDK: $SDK"
echo "============================================"

# Build the Docker image (which compiles the extension)
docker build -f Dockerfile.linux-build --build-arg "SDKS=$SDK" -t fakequeries-linux-build .

# Create output directory
mkdir -p build-output

# Copy the built files out of the container
docker create --name fq-extract fakequeries-linux-build >/dev/null 2>&1 || true
docker rm fq-extract >/dev/null 2>&1 || true
docker create --name fq-extract fakequeries-linux-build >/dev/null 2>&1
docker cp fq-extract:/build/smext-fakequeries/build/fakequeries/. build-output/
docker rm fq-extract >/dev/null 2>&1

echo ""
echo "============================================"
echo " Build complete!"
echo " Output files are in: build-output/"
echo "============================================"
find build-output -name "*.so" -type f 2>/dev/null

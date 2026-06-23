#!/usr/bin/env bash
set -euo pipefail

# Config
BUCKET_NAME="wombat-static"
S3_FOLDER="do-not-delete"
RUST_VERSION="1.95.0"

# Extract version from the git tag (e.g. @biomejs/biome@2.4.16 -> 2.4.16)
BIOME_VERSION=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null | sed 's/.*@//')
if [ -z "$BIOME_VERSION" ]; then
  echo "Error: Could not determine BIOME_VERSION from git tags"
  exit 1
fi
echo "BIOME_VERSION: $BIOME_VERSION"

upload_to_s3() {
  local binary_path="$1"
  local s3_key="$2"

  if [ ! -f "$binary_path" ]; then
    echo "Error: Binary not found at $binary_path"
    exit 1
  fi

  echo "--- Uploading $s3_key ---"
  docker run --rm \
    -v ~/.aws:/root/.aws \
    -v "$(pwd)":/workspace \
    amazon/aws-cli \
    s3 cp --profile wom-static-bucket "/workspace/${binary_path}" "s3://${BUCKET_NAME}/${S3_FOLDER}/${s3_key}"

  echo "S3 URI: s3://${BUCKET_NAME}/${S3_FOLDER}/${s3_key}"
  echo "HTTP URL: https://${BUCKET_NAME}.s3.amazonaws.com/${S3_FOLDER}/${s3_key}"
  echo ""
}

# 1. Build darwin-arm64 (native)
echo "=== Building biome for darwin-arm64 (native) ==="
BIOME_VERSION=${BIOME_VERSION} cargo build --release --bin biome
cp target/release/biome target/release/biome-darwin-arm64

# 2. Build linux-x64 (via cargo-zigbuild in isolated source tree)
echo "=== Building biome for linux-x64 (zigbuild) ==="
mkdir -p target/linux-build-src
rsync -ac --delete --exclude='/target' --exclude='/.git' ./ target/linux-build-src/
(
  cd target/linux-build-src
  AR="zig ar" RANLIB="zig ranlib" BIOME_VERSION=${BIOME_VERSION} cargo zigbuild --release --bin biome --target x86_64-unknown-linux-gnu
)
cp target/linux-build-src/target/x86_64-unknown-linux-gnu/release/biome target/release/biome-linux-x64

# 3. Compress and upload both
echo "=== Compressing binaries ==="
gzip -f target/release/biome-darwin-arm64
gzip -f target/release/biome-linux-x64

echo "=== Uploading binaries to S3 ==="
upload_to_s3 "target/release/biome-darwin-arm64.gz" "biome-darwin-arm64.gz"
upload_to_s3 "target/release/biome-linux-x64.gz" "biome-linux-x64.gz"

echo "=== All uploads complete ==="

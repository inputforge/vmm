#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="$ROOT_DIR/assets/ubuntu-resolute-arm64"
SEED_DIR="$ASSET_DIR/seed"
VMLINUX="$ASSET_DIR/vmlinux"

BASE_URL="https://cloud-images.ubuntu.com/resolute/current"
UNPACKED_URL="$BASE_URL/unpacked"

mkdir -p "$ASSET_DIR" "$SEED_DIR"

download() {
  local url="$1"
  local output="$2"

  if [[ -f "$output" ]]; then
    echo "exists: $output"
    return
  fi

  echo "download: $url"
  curl -fL --retry 3 --output "$output" "$url"
}

download "$UNPACKED_URL/resolute-server-cloudimg-arm64-vmlinuz-generic" "$ASSET_DIR/vmlinuz"
download "$UNPACKED_URL/resolute-server-cloudimg-arm64-initrd-generic" "$ASSET_DIR/initrd.img"
download "$BASE_URL/resolute-server-cloudimg-arm64.squashfs" "$ASSET_DIR/root.squashfs"

if [[ ! -f "$VMLINUX" ]]; then
  if ! command -v zstd >/dev/null 2>&1; then
    echo "error: zstd is required to extract $VMLINUX from vmlinuz" >&2
    exit 1
  fi

  echo "extract: $VMLINUX"
  python3 - "$ASSET_DIR/vmlinuz" "$ASSET_DIR/vmlinuz.zst" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_bytes()
magic = b"\x28\xb5\x2f\xfd"
offset = source.find(magic)

if offset < 0:
    raise SystemExit("zstd payload not found in vmlinuz")

Path(sys.argv[2]).write_bytes(source[offset:])
PY

  rm -f "$VMLINUX.tmp"
  zstd -dc "$ASSET_DIR/vmlinuz.zst" > "$VMLINUX.tmp" 2>/dev/null || true

  if [[ ! -s "$VMLINUX.tmp" ]]; then
    echo "error: failed to extract $VMLINUX" >&2
    rm -f "$VMLINUX.tmp" "$ASSET_DIR/vmlinuz.zst"
    exit 1
  fi

  mv "$VMLINUX.tmp" "$VMLINUX"
  rm -f "$ASSET_DIR/vmlinuz.zst"
fi

if [[ ! -f "$ASSET_DIR/overlay.raw" ]]; then
  echo "create: $ASSET_DIR/overlay.raw"
  mkfile -n 8g "$ASSET_DIR/overlay.raw"
fi

cat > "$SEED_DIR/meta-data" <<'EOF'
instance-id: vmm-resolute-arm64
local-hostname: vmm
EOF

cat > "$SEED_DIR/user-data" <<'EOF'
#cloud-config
users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    plain_text_passwd: ubuntu
chpasswd:
  expire: false
ssh_pwauth: true
disable_root: false
package_update: false
final_message: "vmm cloud-init complete"
EOF

rm -f "$ASSET_DIR/seed.iso"
hdiutil makehybrid \
  -iso \
  -joliet \
  -default-volume-name cidata \
  -o "$ASSET_DIR/seed.iso" \
  "$SEED_DIR" >/dev/null

echo
echo "Ubuntu Resolute ARM64 assets are ready in $ASSET_DIR"
echo "Run:"
echo "  make run"
echo
echo "Console login:"
echo "  username: ubuntu"
echo "  password: ubuntu"

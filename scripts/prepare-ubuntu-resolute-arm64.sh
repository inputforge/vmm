#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="$ROOT_DIR/assets/ubuntu-resolute-arm64"
SEED_DIR="$ASSET_DIR/seed"

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

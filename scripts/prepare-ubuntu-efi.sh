#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="$ROOT_DIR/assets/ubuntu-efi"
SEED_DIR="$ASSET_DIR/seed"
SEED_IMG="$ASSET_DIR/seed.img"

SSH_KEY="${1:-}"
if [[ -z "$SSH_KEY" ]]; then
  for candidate in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ecdsa.pub"; do
    if [[ -f "$candidate" ]]; then
      SSH_KEY="$(cat "$candidate")"
      break
    fi
  done
fi

if [[ -z "$SSH_KEY" ]]; then
  echo "error: no SSH public key found; pass one as argument or create ~/.ssh/id_ed25519" >&2
  exit 1
fi

mkdir -p "$SEED_DIR"

cat > "$SEED_DIR/meta-data" <<EOF
instance-id: vmm-ubuntu-efi
local-hostname: ubuntu-efi
EOF

cat > "$SEED_DIR/user-data" <<EOF
#cloud-config
users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    plain_text_passwd: ubuntu
    ssh_authorized_keys:
      - $SSH_KEY
chpasswd:
  expire: false
ssh_pwauth: true
disable_root: false
package_update: false
final_message: "vmm cloud-init complete"
EOF

# VZDiskImageStorageDeviceAttachment does not accept ISO 9660 images.
# Create a raw FAT16 disk image that the guest sees as a plain virtio-blk device.
rm -f "$SEED_IMG"
dd if=/dev/zero of="$SEED_IMG" bs=1024 count=4096 2>/dev/null

DEVICE=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount "$SEED_IMG" | awk '{print $1}')

newfs_msdos -F 12 -v CIDATA "$DEVICE" >/dev/null

diskutil mount "$DEVICE" >/dev/null
MOUNTPOINT=$(diskutil info "$DEVICE" | awk -F': +' '/Mount Point/{print $2}')

cp "$SEED_DIR/meta-data" "$SEED_DIR/user-data" "$MOUNTPOINT/"

diskutil unmount "$DEVICE" >/dev/null
hdiutil detach "$DEVICE" -quiet

echo "seed.img written to $SEED_IMG"
echo
echo "Console login: ubuntu / ubuntu"
echo "SSH key: ${SSH_KEY:0:40}..."

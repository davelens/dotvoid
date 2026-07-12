#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
# run.sh — boot the Void live ISO in QEMU (UEFI) with a fresh disk and
# this repo shared into the guest over virtio-9p.
#
#   ./vm/install.sh        # recommended: fully unattended fresh install
#   ./vm/run.sh            # manual debugging: live ISO + existing/new disk
#   ./vm/run.sh --fresh    # manual debugging with a fresh disk
#
# Inside the VM, log in as root (password: voidlinux), then run:
#
#   mkdir -p /media/repo
#   mount -t 9p -o trans=virtio,version=9p2000.L repo /media/repo
#   FORCE=1 /media/repo/scripts/install.sh /media/repo/config/vm.env
#   poweroff
#
# Then verify the result boots on its own with ./vm/test.sh
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

# shellcheck source=vm/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 not found"
[ -f "$ISO_PATH" ] || die "ISO missing; run ./vm/fetch-iso.sh first"

mkdir -p "$STATE_DIR"
setup_uefi

if [ "${1:-}" = "--fresh" ]; then
  log "Removing old disk + UEFI vars"
  rm -f "$DISK_PATH" "$OVMF_VARS"
  setup_uefi
fi

if [ ! -f "$DISK_PATH" ]; then
  log "Creating $DISK_SIZE disk at $DISK_PATH"
  qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
fi

log "Booting live ISO (repo shared as 9p tag 'repo')"
cat <<'EOF'
──────────────────────────────────────────────────────────────
Inside the VM (login root / voidlinux):

  mkdir -p /media/repo
  mount -t 9p -o trans=virtio,version=9p2000.L repo /media/repo
  FORCE=1 /media/repo/scripts/install.sh /media/repo/config/vm.env
  poweroff

Afterwards: ./vm/test.sh to boot the installed system.
──────────────────────────────────────────────────────────────
EOF

exec qemu-system-x86_64 \
  -enable-kvm \
  -machine q35,accel=kvm \
  -cpu host \
  -smp "$VM_CPUS" \
  -m "$VM_MEM" \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS" \
  -drive file="$DISK_PATH",if=virtio,format=qcow2 \
  -cdrom "$ISO_PATH" \
  -boot order=d \
  -virtfs "local,path=$REPO_ROOT,mount_tag=repo,security_model=none,readonly=on" \
  -nic user,model=virtio-net-pci \
  -display gtk \
  -name void-install-test

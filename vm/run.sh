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

if [ "${1:-}" = "--fresh" ] || [ ! -f "$DISK_PATH" ]; then
  vm_fresh_disk
else
  setup_uefi
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

vm_qemu_argv live
exec "${VM_QEMU[@]}"

#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
# test.sh — boot the INSTALLED disk (no ISO attached) to verify the
# system produced by install.sh actually boots via UEFI.
#
#   ./vm/test.sh
#
# Login: root / voidlinux (from config/vm.env). sshd is enabled in the
# VM config; port 22 is forwarded to localhost:2222, so you can also:
#
#   ssh -p 2222 root@localhost
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

# shellcheck source=vm/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 not found"
[ -f "$DISK_PATH" ] || die "no VM disk found; run ./vm/run.sh and install first"
setup_uefi

log "Booting installed system from $DISK_PATH (ssh: port 2222)"

exec qemu-system-x86_64 \
  -enable-kvm \
  -machine q35,accel=kvm \
  -cpu host \
  -smp "$VM_CPUS" \
  -m "$VM_MEM" \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS" \
  -drive file="$DISK_PATH",if=virtio,format=qcow2 \
  -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
  -display gtk \
  -name void-boot-test

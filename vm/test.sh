#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
# test.sh — boot the INSTALLED disk (no ISO attached) to verify the
# system produced by install.sh actually boots via UEFI.
#
#   ./vm/test.sh
#
# Login: davelens / voidlinux (from config/vm.env). sshd is enabled in the
# VM config; port 22 is forwarded to localhost:2222, so you can also:
#
#   ssh -p 2222 davelens@localhost
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

# shellcheck source=vm/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 not found"
[ -f "$DISK_PATH" ] || die "no VM disk found; run ./vm/install.sh first"
setup_uefi

log "Booting installed system from $DISK_PATH (ssh: port 2222)"

vm_qemu_argv installed
exec "${VM_QEMU[@]}"

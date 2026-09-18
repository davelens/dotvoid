#!/bin/bash
# Fully unattended QEMU install. Always recreates the test disk.
#
#   ./vm/install.sh
#   ./vm/test.sh       # boot the result afterwards
set -euo pipefail

# shellcheck source=vm/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

for cmd in qemu-system-x86_64 qemu-img bsdtar python3; do
  command -v "$cmd" >/dev/null || die "missing command: $cmd"
done
[ -f "$ISO_PATH" ] || die "ISO missing; run ./vm/fetch-iso.sh first"

mkdir -p "$STATE_DIR"

# Extract before touching the disk so a bad ISO aborts with nothing lost.
vm_extract_live_kernel
vm_fresh_disk

log "Starting unattended Void installation"
vm_qemu_argv auto-install
python3 "$VM_DIR/auto-install.py" "${VM_QEMU[@]}"

log "Run ./vm/test.sh to boot the installed system"

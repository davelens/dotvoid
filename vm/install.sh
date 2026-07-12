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

# Direct kernel boot lets the host drive the live system over ttyS0. The
# target still boots and installs under OVMF, so /sys/firmware/efi exists.
LIVE_KERNEL="$STATE_DIR/vmlinuz"
LIVE_INITRD="$STATE_DIR/initrd"
if [ ! -f "$LIVE_KERNEL" ] || [ ! -f "$LIVE_INITRD" ]; then
  log "Extracting kernel and initrd from the live ISO"
  bsdtar -xOf "$ISO_PATH" boot/vmlinuz >"$LIVE_KERNEL"
  bsdtar -xOf "$ISO_PATH" boot/initrd >"$LIVE_INITRD"
fi

log "Recreating $DISK_SIZE VM disk"
rm -f "$DISK_PATH" "$STATE_DIR/OVMF_VARS.fd"
qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
setup_uefi

log "Starting unattended Void installation"
python3 "$VM_DIR/auto-install.py" \
  qemu-system-x86_64 \
  -enable-kvm \
  -machine q35,accel=kvm \
  -cpu host \
  -smp "$VM_CPUS" \
  -m "$VM_MEM" \
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
  -drive "if=pflash,format=raw,file=$OVMF_VARS" \
  -kernel "$LIVE_KERNEL" \
  -initrd "$LIVE_INITRD" \
  -append "root=live:CDLABEL=VOID_LIVE ro init=/sbin/init rd.luks=0 rd.md=0 rd.dm=0 loglevel=4 console=ttyS0 rd.live.overlay.overlayfs=1" \
  -cdrom "$ISO_PATH" \
  -drive "file=$DISK_PATH,if=virtio,format=qcow2" \
  -virtfs "local,path=$REPO_ROOT,mount_tag=repo,security_model=none,readonly=on" \
  -nic user,model=virtio-net-pci \
  -nographic \
  -name void-auto-install

log "Run ./vm/test.sh to boot the installed system"

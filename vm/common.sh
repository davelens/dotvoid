#!/bin/bash
# Shared settings for the QEMU harness. Sourced by the other vm/ scripts.
# shellcheck disable=SC2034  # variables are consumed by sourcing scripts

VOID_VERSION="20250202"
VOID_MIRROR="https://repo-default.voidlinux.org/live/$VOID_VERSION"
ISO_NAME="void-live-x86_64-${VOID_VERSION}-base.iso"

VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$VM_DIR")"
# Overridable so host-side tests can point the harness at a scratch dir.
STATE_DIR="${STATE_DIR:-$VM_DIR/state}"

ISO_PATH="$STATE_DIR/$ISO_NAME"
DISK_PATH="$STATE_DIR/void-vm.qcow2"
LIVE_KERNEL="$STATE_DIR/${ISO_NAME}.vmlinuz"
LIVE_INITRD="$STATE_DIR/${ISO_NAME}.initrd"
DISK_SIZE="25G"
VM_MEM="4G"
VM_CPUS="4"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

verify_iso() {
  local manifest=$1 iso_path=$2 digest

  if ! digest=$(awk -v name="$ISO_NAME" '
    BEGIN { prefix = "SHA256 (" name ") = " }
    index($0, prefix) == 1 {
      count++
      digest = substr($0, length(prefix) + 1)
    }
    END {
      if (count == 1) {
        print digest
      } else if (count == 0) {
        print "error: checksum manifest has no BSD record for " name > "/dev/stderr"
        exit 1
      } else {
        print "error: checksum manifest has duplicate BSD records for " name > "/dev/stderr"
        exit 1
      }
    }
  ' "$manifest"); then
    return 1
  fi

  if ! printf '%s  %s\n' "$digest" "$iso_path" | sha256sum -c -; then
    printf 'error: checksum verification failed for %s\n' "$ISO_NAME" >&2
    return 1
  fi
}

# Locate OVMF UEFI firmware across distros.
find_ovmf_code() {
  local p
  for p in \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2/x64/OVMF_CODE.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE_4M.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/qemu/ovmf-x86_64-code.bin; do
    [ -f "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

find_ovmf_vars() {
  local p
  for p in \
    /usr/share/edk2/x64/OVMF_VARS.4m.fd \
    /usr/share/edk2/x64/OVMF_VARS.fd \
    /usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
    /usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/qemu/ovmf-x86_64-vars.bin; do
    [ -f "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

# OVMF_CODE and OVMF_VARS_TEMPLATE may be preset in the environment for
# non-standard firmware paths (and for host-side tests).
setup_uefi() {
  if [ -z "${OVMF_CODE:-}" ]; then
    OVMF_CODE="$(find_ovmf_code)" || die "OVMF firmware not found (install edk2-ovmf)"
  fi
  # Writable per-VM copy of the UEFI variable store.
  OVMF_VARS="$STATE_DIR/OVMF_VARS.fd"
  if [ ! -f "$OVMF_VARS" ]; then
    if [ -z "${OVMF_VARS_TEMPLATE:-}" ]; then
      OVMF_VARS_TEMPLATE="$(find_ovmf_vars)" || die "OVMF vars template not found"
    fi
    cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
  fi
}

# Download + verify the live ISO if it is not cached yet.
vm_ensure_iso() {
  [ -f "$ISO_PATH" ] || "$VM_DIR/fetch-iso.sh"
}

# Discard the disk and UEFI variable store, then create both fresh.
vm_fresh_disk() {
  log "Recreating $DISK_SIZE VM disk"
  rm -f "$DISK_PATH" "$STATE_DIR/OVMF_VARS.fd"
  qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
  setup_uefi
}

# Extract kernel + initrd from the live ISO for direct kernel boot.
vm_extract_live_kernel() {
  log "Extracting kernel and initrd from the live ISO"
  bsdtar -xOf "$ISO_PATH" boot/vmlinuz >"$LIVE_KERNEL"
  [ -s "$LIVE_KERNEL" ] || die "extracted live kernel is empty"
  bsdtar -xOf "$ISO_PATH" boot/initrd >"$LIVE_INITRD"
  [ -s "$LIVE_INITRD" ] || die "extracted live initrd is empty"
}

# Fill VM_QEMU with the qemu argv for one of three modes:
#   live          boot the live ISO graphically with the repo shared over 9p
#   auto-install  direct-kernel boot of the live system on ttyS0, for
#                 auto-install.py to drive
#   installed     boot only the installed disk, ssh forwarded to 127.0.0.1:2222
# Callers exec the array or hand it to the serial driver.
vm_qemu_argv() {
  local mode=$1

  # shellcheck disable=SC2054  # one qemu argument per line
  VM_QEMU=(
    qemu-system-x86_64
    -enable-kvm
    -machine q35,accel=kvm
    -cpu host
    -smp "$VM_CPUS"
    -m "$VM_MEM"
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$OVMF_VARS"
    -drive "file=$DISK_PATH,if=virtio,format=qcow2"
  )
  case "$mode" in
    live)
      # shellcheck disable=SC2054
      VM_QEMU+=(
        -cdrom "$ISO_PATH"
        -boot order=d
        -virtfs "local,path=$REPO_ROOT,mount_tag=repo,security_model=none,readonly=on"
        -nic user,model=virtio-net-pci
        -device virtio-vga
        -display gtk
        -name void-install-test
      )
      ;;
    auto-install)
      # Direct kernel boot lets the host drive the live system over ttyS0.
      # The target still boots and installs under OVMF, so /sys/firmware/efi
      # exists.
      # shellcheck disable=SC2054
      VM_QEMU+=(
        -kernel "$LIVE_KERNEL"
        -initrd "$LIVE_INITRD"
        -append "root=live:CDLABEL=VOID_LIVE ro init=/sbin/init rd.luks=0 rd.md=0 rd.dm=0 loglevel=4 console=ttyS0 rd.live.overlay.overlayfs=1"
        -cdrom "$ISO_PATH"
        -virtfs "local,path=$REPO_ROOT,mount_tag=repo,security_model=none,readonly=on"
        -nic user,model=virtio-net-pci
        -nographic
        -name void-auto-install
      )
      ;;
    installed)
      # A DRM-capable GPU so a wlroots compositor (sway) can start.
      # shellcheck disable=SC2054
      VM_QEMU+=(
        -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22
        -device virtio-vga
        -display gtk
        -name void-boot-test
      )
      ;;
    *) die "unknown VM mode: $mode" ;;
  esac
}

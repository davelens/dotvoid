#!/bin/bash
# Shared settings for the QEMU harness. Sourced by the other vm/ scripts.
# shellcheck disable=SC2034  # variables are consumed by sourcing scripts

VOID_VERSION="20250202"
VOID_MIRROR="https://repo-default.voidlinux.org/live/current"
ISO_NAME="void-live-x86_64-${VOID_VERSION}-base.iso"

VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$VM_DIR")"
STATE_DIR="$VM_DIR/state"

ISO_PATH="$STATE_DIR/$ISO_NAME"
DISK_PATH="$STATE_DIR/void-vm.qcow2"
DISK_SIZE="25G"
VM_MEM="4G"
VM_CPUS="4"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

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

setup_uefi() {
  OVMF_CODE="$(find_ovmf_code)" || die "OVMF firmware not found (install edk2-ovmf)"
  # Writable per-VM copy of the UEFI variable store.
  OVMF_VARS="$STATE_DIR/OVMF_VARS.fd"
  if [ ! -f "$OVMF_VARS" ]; then
    cp "$(find_ovmf_vars)" "$OVMF_VARS" || die "OVMF vars template not found"
  fi
}

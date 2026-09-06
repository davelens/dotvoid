#!/bin/bash
# Host-only tests for installer safety checks. All system inspection is mocked.
set -euo pipefail

case ${BASH_SOURCE[0]} in
  */*) TEST_DIR=${BASH_SOURCE[0]%/*} ;;
  *)   TEST_DIR=. ;;
esac
# shellcheck source=scripts/install-safety.sh
. "$TEST_DIR/../scripts/install-safety.sh"
# shellcheck source=vm/common.sh
. "$TEST_DIR/common.sh"

if grep -Fq 'hostfwd=tcp:127.0.0.1:2222-:22' "$TEST_DIR/test.sh"; then
  printf 'ok - SSH forwarding is loopback-only\n'
else
  printf 'not ok - SSH forwarding is not loopback-only\n' >&2
  exit 1
fi

MOCK_TYPE=disk
MOCK_TYPE_STATUS=0
MOCK_MOUNTPOINTS=
MOCK_MOUNT_STATUS=0
MOCK_FINDMNT_TARGETS=/
MOCK_FINDMNT_STATUS=0

lsblk() {
  local arg nodeps=0

  for arg in "$@"; do
    [ "$arg" = "--nodeps" ] && nodeps=1
  done
  if [ "$nodeps" -eq 1 ]; then
    printf '%s' "$MOCK_TYPE"
    return "$MOCK_TYPE_STATUS"
  fi
  printf '%s' "$MOCK_MOUNTPOINTS"
  return "$MOCK_MOUNT_STATUS"
}

findmnt() {
  printf '%s' "$MOCK_FINDMNT_TARGETS"
  return "$MOCK_FINDMNT_STATUS"
}

reset_mocks() {
  MOCK_TYPE=disk
  MOCK_TYPE_STATUS=0
  MOCK_MOUNTPOINTS=
  MOCK_MOUNT_STATUS=0
  MOCK_FINDMNT_TARGETS=/
  MOCK_FINDMNT_STATUS=0
}

accepts() {
  local name=$1

  if install_safety_check_target /dev/mock /mnt; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s (unexpected rejection: %s)\n' \
      "$name" "$INSTALL_SAFETY_ERROR" >&2
    return 1
  fi
}

rejects() {
  local name=$1

  if install_safety_check_target /dev/mock /mnt; then
    printf 'not ok - %s (unexpected acceptance)\n' "$name" >&2
    return 1
  fi
  printf 'ok - %s\n' "$name"
}

reset_mocks
accepts "clean whole disk"

reset_mocks
MOCK_TYPE=part
rejects "partition target"

reset_mocks
MOCK_TYPE=crypt
rejects "device-mapper target"

reset_mocks
MOCK_MOUNTPOINTS=/media/data
rejects "mounted target descendant"

reset_mocks
MOCK_MOUNTPOINTS='[SWAP]'
rejects "target descendant used as swap"

reset_mocks
MOCK_FINDMNT_TARGETS=$'/\n/mnt'
rejects "occupied /mnt"

reset_mocks
MOCK_FINDMNT_TARGETS=$'/\n/mnt/nested'
rejects "occupied /mnt subtree"

reset_mocks
MOCK_TYPE_STATUS=1
rejects "target type inspection error"

reset_mocks
MOCK_MOUNT_STATUS=1
rejects "target mount inspection error"

reset_mocks
MOCK_FINDMNT_STATUS=1
rejects "mount tree inspection error"

verify_accepts() {
  local name=$1 manifest=$2 iso_path=$3 output

  if output=$(verify_iso "$manifest" "$iso_path" 2>&1); then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s (unexpected rejection: %s)\n' "$name" "$output" >&2
    return 1
  fi
}

verify_rejects() {
  local name=$1 manifest=$2 iso_path=$3

  if verify_iso "$manifest" "$iso_path" >/dev/null 2>&1; then
    printf 'not ok - %s (unexpected acceptance)\n' "$name" >&2
    return 1
  fi
  printf 'ok - %s\n' "$name"
}

TMP_DIR=$(mktemp -d "$TEST_DIR/.test-host.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
ISO_NAME=dummy.iso
DUMMY_ISO="$TMP_DIR/$ISO_NAME"
OTHER_ISO="$TMP_DIR/unrelated.iso"
printf 'dummy ISO contents\n' > "$DUMMY_ISO"
printf 'unrelated ISO contents\n' > "$OTHER_ISO"
DUMMY_DIGEST=$(sha256sum "$DUMMY_ISO" | awk '{print $1}')
OTHER_DIGEST=$(sha256sum "$OTHER_ISO" | awk '{print $1}')

printf 'SHA256 (%s) = %s\n' "$ISO_NAME" "$DUMMY_DIGEST" > "$TMP_DIR/valid.txt"
verify_accepts "valid ISO checksum" "$TMP_DIR/valid.txt" "$DUMMY_ISO"

printf 'SHA256 (unrelated.iso) = %s\n' "$OTHER_DIGEST" > "$TMP_DIR/missing.txt"
verify_rejects "missing selected ISO checksum" "$TMP_DIR/missing.txt" "$DUMMY_ISO"

printf 'SHA256 (%s) = %s\nSHA256 (%s) = %s\n' \
  "$ISO_NAME" "$DUMMY_DIGEST" "$ISO_NAME" "$DUMMY_DIGEST" > "$TMP_DIR/duplicate.txt"
verify_rejects "duplicate selected ISO checksum" "$TMP_DIR/duplicate.txt" "$DUMMY_ISO"

printf 'SHA256 (%s) = %064d\n' "$ISO_NAME" 0 > "$TMP_DIR/corrupt.txt"
verify_rejects "corrupt ISO checksum" "$TMP_DIR/corrupt.txt" "$DUMMY_ISO"

# Run a copy of install.sh with host-only mocks. An empty initrd must abort
# before disk recreation, and the retry must replace both extraction outputs.
INSTALL_SANDBOX="$TMP_DIR/install-sandbox"
INSTALL_ISO_NAME=void-live-x86_64-20990101-base.iso
mkdir -p "$INSTALL_SANDBOX/state"
cp "$TEST_DIR/install.sh" "$INSTALL_SANDBOX/install.sh"
cat > "$INSTALL_SANDBOX/common.sh" <<'EOF'
ISO_NAME=void-live-x86_64-20990101-base.iso
VM_DIR=$HARNESS_DIR
REPO_ROOT=$HARNESS_DIR
STATE_DIR=$HARNESS_DIR/state
ISO_PATH=$STATE_DIR/$ISO_NAME
DISK_PATH=$STATE_DIR/void-vm.qcow2
DISK_SIZE=1G
VM_MEM=1G
VM_CPUS=1
log() { :; }
die() { exit 1; }
bsdtar() {
  if [ "$(cat "$HARNESS_DIR/extract-mode")" = empty ]; then
    if [ "$3" = boot/vmlinuz ]; then
      printf 'stale-kernel\n'
    fi
    return 0
  elif [ "$3" = boot/vmlinuz ]; then
    printf 'fresh-kernel\n'
  else
    printf 'fresh-initrd\n'
  fi
}
qemu-system-x86_64() { :; }
qemu-img() { printf 'qemu-img\n' >> "$HARNESS_DIR/vm-commands"; }
python3() { printf 'python3\n' >> "$HARNESS_DIR/vm-commands"; }
setup_uefi() {
  OVMF_CODE=$HARNESS_DIR/OVMF_CODE.fd
  OVMF_VARS=$STATE_DIR/OVMF_VARS.fd
  : > "$OVMF_VARS"
}
EOF
printf 'mock ISO\n' > "$INSTALL_SANDBOX/state/$INSTALL_ISO_NAME"
export HARNESS_DIR=$INSTALL_SANDBOX
printf 'empty\n' > "$INSTALL_SANDBOX/extract-mode"
if bash "$INSTALL_SANDBOX/install.sh" >/dev/null 2>&1; then
  printf 'not ok - empty extraction was accepted\n' >&2
  exit 1
fi
if [ -e "$INSTALL_SANDBOX/vm-commands" ]; then
  printf 'not ok - empty extraction touched disk or VM\n' >&2
  exit 1
fi
printf 'success\n' > "$INSTALL_SANDBOX/extract-mode"
bash "$INSTALL_SANDBOX/install.sh" >/dev/null 2>&1
if [ "$(cat "$INSTALL_SANDBOX/state/$INSTALL_ISO_NAME.vmlinuz")" != fresh-kernel ] ||
   [ "$(cat "$INSTALL_SANDBOX/state/$INSTALL_ISO_NAME.initrd")" != fresh-initrd ]; then
  printf 'not ok - retry reused an earlier extraction\n' >&2
  exit 1
fi
printf 'ok - empty extraction is rejected and regenerated on retry\n'

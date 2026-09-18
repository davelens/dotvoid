#!/bin/bash
# Host-only tests for installer safety checks. All system inspection is mocked.
set -euo pipefail

case ${BASH_SOURCE[0]} in
  */*) TEST_DIR=${BASH_SOURCE[0]%/*} ;;
  *)   TEST_DIR=. ;;
esac
# shellcheck source=scripts/install-profile.sh
. "$TEST_DIR/../scripts/install-profile.sh"
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

# Profile loading runs in a subshell so each fixture starts from a clean
# environment. readlink is mocked because fixture disks do not exist.
readlink() { printf '%s\n' "${*: -1}"; }

write_profile() {
  local path=$1
  shift
  printf '%s\n' "$@" > "$path"
}

profile_accepts() {
  local name=$1 config=$2 expect=$3 output

  if output=$(
    install_profile_load "$config" || { echo "$INSTALL_PROFILE_ERROR"; exit 1; }
    echo "$REPO_URL $ARCH $DISK $ESP_DEV $ROOT_DEV"
  ) && [ "$output" = "$expect" ]; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s (got: %s)\n' "$name" "$output" >&2
    return 1
  fi
}

profile_rejects() {
  local name=$1 config=$2 expect=$3 output

  output=$(install_profile_load "$config" && echo accepted || echo "$INSTALL_PROFILE_ERROR")
  case "$output" in
    accepted)
      printf 'not ok - %s (unexpected acceptance)\n' "$name" >&2
      return 1
      ;;
    *"$expect"*) printf 'ok - %s\n' "$name" ;;
    *)
      printf 'not ok - %s (unexpected error: %s)\n' "$name" "$output" >&2
      return 1
      ;;
  esac
}

BASE_PROFILE=(
  'DISK=/dev/sda' 'HOSTNAME=h' 'USERNAME=u' 'USER_GROUPS=wheel'
  'TIMEZONE=UTC' 'KEYMAP=us' 'LOCALE=en_US.UTF-8' 'LIBC=glibc'
  'MIRROR=https://mirror.example' 'ESP_SIZE_MIB=512' 'BTRFS_OPTS=noatime'
  'SUBVOLUMES="@=/ @home=/home"' 'PACKAGES=base-system' 'SERVICES=dbus'
)

write_profile "$TMP_DIR/glibc.env" "${BASE_PROFILE[@]}"
profile_accepts "glibc profile on sd disk" "$TMP_DIR/glibc.env" \
  "https://mirror.example/current x86_64 /dev/sda /dev/sda1 /dev/sda2"

write_profile "$TMP_DIR/musl.env" "${BASE_PROFILE[@]}" 'LIBC=musl' 'LOCALE=' \
  'DISK=/dev/nvme0n1'
profile_accepts "musl profile on nvme disk" "$TMP_DIR/musl.env" \
  "https://mirror.example/current/musl x86_64-musl /dev/nvme0n1 /dev/nvme0n1p1 /dev/nvme0n1p2"

profile_rejects "missing config" "$TMP_DIR/absent.env" "config not found"

write_profile "$TMP_DIR/nohost.env" "${BASE_PROFILE[@]}" 'HOSTNAME='
profile_rejects "missing required setting" "$TMP_DIR/nohost.env" \
  "HOSTNAME is not set"

write_profile "$TMP_DIR/nolocale.env" "${BASE_PROFILE[@]}" 'LOCALE='
profile_rejects "glibc without LOCALE" "$TMP_DIR/nolocale.env" "LOCALE is not set"

write_profile "$TMP_DIR/badlibc.env" "${BASE_PROFILE[@]}" 'LIBC=uclibc'
profile_rejects "unknown LIBC" "$TMP_DIR/badlibc.env" "LIBC must be glibc or musl"

write_profile "$TMP_DIR/badroot.env" "${BASE_PROFILE[@]}" \
  'SUBVOLUMES="@home=/home @=/"'
profile_rejects "first subvolume not at /" "$TMP_DIR/badroot.env" \
  "first SUBVOLUMES entry must mount at /"

for real in default vm; do
  write_profile "$TMP_DIR/$real.env" \
    ". '$TEST_DIR/../config/$real.env'" 'DISK=/dev/sda'
  if (install_profile_load "$TMP_DIR/$real.env"); then
    printf 'ok - config/%s.env loads\n' "$real"
  else
    printf 'not ok - config/%s.env does not load\n' "$real" >&2
    exit 1
  fi
done

EXPECTED_FSTAB='# generated by install.sh
UUID=root-uuid / btrfs noatime,subvol=@ 0 0
UUID=root-uuid /home btrfs noatime,subvol=@home 0 0
UUID=esp-uuid /boot/efi vfat defaults 0 2
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0'
if [ "$(install_profile_load "$TMP_DIR/glibc.env" \
         && install_profile_fstab root-uuid esp-uuid)" = "$EXPECTED_FSTAB" ]; then
  printf 'ok - fstab rendering\n'
else
  printf 'not ok - fstab rendering\n' >&2
  exit 1
fi

# A dumped profile must round-trip through a fresh load without the base
# config it was layered on.
write_profile "$TMP_DIR/layered.env" ". '$TMP_DIR/glibc.env'" 'HOSTNAME="two words"'
(
  install_profile_load "$TMP_DIR/layered.env" || exit 1
  install_profile_dump > "$TMP_DIR/dumped.env"
) || { printf 'not ok - layered profile load\n' >&2; exit 1; }
rm -f "$TMP_DIR/glibc.env"
if output=$(install_profile_load "$TMP_DIR/dumped.env" && echo "$HOSTNAME") \
   && [ "$output" = "two words" ]; then
  printf 'ok - dumped profile round-trips\n'
else
  printf 'not ok - dumped profile round-trips (got: %s)\n' "$output" >&2
  exit 1
fi

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

#!/bin/bash
# Host-only tests for the installer and the QEMU harness. All system
# inspection and external commands are mocked; nothing boots.
set -euo pipefail

case ${BASH_SOURCE[0]} in
  */*) TEST_DIR=${BASH_SOURCE[0]%/*} ;;
  *)   TEST_DIR=. ;;
esac
TMP_DIR=$(mktemp -d "$TEST_DIR/.test-host.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

# shellcheck source=scripts/install-profile.sh
. "$TEST_DIR/../scripts/install-profile.sh"
# shellcheck source=scripts/install-safety.sh
. "$TEST_DIR/../scripts/install-safety.sh"
# Point the harness at scratch state before sourcing it.
export STATE_DIR="$TMP_DIR/state"
mkdir -p "$STATE_DIR"
# shellcheck source=vm/common.sh
. "$TEST_DIR/common.sh"

argv_has() {
  local name=$1 mode=$2 needle=$3

  vm_qemu_argv "$mode"
  case " ${VM_QEMU[*]} " in
    *"$needle"*) printf 'ok - %s\n' "$name" ;;
    *)
      printf 'not ok - %s (missing %s)\n' "$name" "$needle" >&2
      return 1
      ;;
  esac
}

argv_lacks() {
  local name=$1 mode=$2 needle=$3

  vm_qemu_argv "$mode"
  case " ${VM_QEMU[*]} " in
    *"$needle"*)
      printf 'not ok - %s (unexpected %s)\n' "$name" "$needle" >&2
      return 1
      ;;
    *) printf 'ok - %s\n' "$name" ;;
  esac
}

OVMF_CODE=/mock/OVMF_CODE.fd
OVMF_VARS="$STATE_DIR/OVMF_VARS.fd"
argv_has "SSH forwarding is loopback-only" installed \
  'hostfwd=tcp:127.0.0.1:2222-:22'
argv_lacks "installed disk boots without the ISO" installed '-cdrom'
argv_has "installed disk has a DRM-capable GPU for sway" installed 'virtio-vga'
argv_has "live boot shares the repo over 9p" live 'mount_tag=repo'
argv_has "auto-install boots the extracted kernel" auto-install \
  "-kernel $LIVE_KERNEL"
argv_has "auto-install runs headless on ttyS0" auto-install '-nographic'
if (vm_qemu_argv bogus) 2>/dev/null; then
  printf 'not ok - unknown VM mode was accepted\n' >&2
  exit 1
fi
printf 'ok - unknown VM mode is rejected\n'

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

# Run the real vm/install.sh against the scratch STATE_DIR with its external
# commands replaced by exported functions. An empty initrd must abort before
# disk recreation, and the retry must replace both extraction outputs.
bsdtar() {
  if [ "$(cat "$STATE_DIR/extract-mode")" = empty ]; then
    [ "$3" = boot/vmlinuz ] && printf 'stale-kernel\n'
    return 0
  elif [ "$3" = boot/vmlinuz ]; then
    printf 'fresh-kernel\n'
  else
    printf 'fresh-initrd\n'
  fi
}
qemu-system-x86_64() { :; }
qemu-img() { printf 'qemu-img\n' >> "$STATE_DIR/vm-commands"; }
python3() { printf 'python3\n' >> "$STATE_DIR/vm-commands"; }
export -f bsdtar qemu-system-x86_64 qemu-img python3
export OVMF_CODE=/mock/OVMF_CODE.fd OVMF_VARS_TEMPLATE="$TMP_DIR/OVMF_VARS.fd"
: > "$OVMF_VARS_TEMPLATE"

printf 'mock ISO\n' > "$ISO_PATH"
printf 'empty\n' > "$STATE_DIR/extract-mode"
if bash "$TEST_DIR/install.sh" >/dev/null 2>&1; then
  printf 'not ok - empty extraction was accepted\n' >&2
  exit 1
fi
if [ -e "$STATE_DIR/vm-commands" ]; then
  printf 'not ok - empty extraction touched disk or VM\n' >&2
  exit 1
fi
printf 'success\n' > "$STATE_DIR/extract-mode"
bash "$TEST_DIR/install.sh" >/dev/null 2>&1
if [ "$(cat "$LIVE_KERNEL")" != fresh-kernel ] ||
   [ "$(cat "$LIVE_INITRD")" != fresh-initrd ]; then
  printf 'not ok - retry reused an earlier extraction\n' >&2
  exit 1
fi
if [ "$(cat "$STATE_DIR/vm-commands")" != $'qemu-img\npython3' ]; then
  printf 'not ok - install did not recreate the disk then start the VM\n' >&2
  exit 1
fi
printf 'ok - empty extraction is rejected and regenerated on retry\n'

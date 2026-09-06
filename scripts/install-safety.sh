#!/bin/bash
# Safety checks shared by the installer and host-side tests.
# INSTALL_SAFETY_ERROR is read by callers after a failed check.
# shellcheck disable=SC2034

install_safety_check_target() {
  local disk=$1 target=$2 disk_type mountpoints mount_targets mount_target

  INSTALL_SAFETY_ERROR=

  if ! disk_type="$(lsblk --noheadings --raw --nodeps --output TYPE -- "$disk")"; then
    INSTALL_SAFETY_ERROR="could not inspect target type with lsblk: $disk"
    return 1
  fi
  if [ "$disk_type" != "disk" ]; then
    INSTALL_SAFETY_ERROR="target is not a whole disk: $disk (lsblk type: ${disk_type:-unknown})"
    return 1
  fi

  if ! mountpoints="$(lsblk --noheadings --raw --output MOUNTPOINTS -- "$disk")"; then
    INSTALL_SAFETY_ERROR="could not inspect target mount state with lsblk: $disk"
    return 1
  fi
  if [ -n "$mountpoints" ]; then
    INSTALL_SAFETY_ERROR="target or a descendant is mounted or used as swap: $disk"
    return 1
  fi

  if ! mount_targets="$(findmnt --kernel --noheadings --raw --output TARGET)"; then
    INSTALL_SAFETY_ERROR="could not inspect mount tree with findmnt"
    return 1
  fi
  while IFS= read -r mount_target; do
    case "$mount_target" in
      "$target"|"$target"/*)
        INSTALL_SAFETY_ERROR="install mount tree is already occupied: $mount_target"
        return 1
        ;;
    esac
  done <<< "$mount_targets"

  return 0
}

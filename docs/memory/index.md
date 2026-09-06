# Project memory

- dotvoid installs a minimal x86_64 Void Linux base system; personalized desktop provisioning belongs in the separate dotsys repository.
- The installer targets UEFI/GRUB and btrfs. Machine profiles are trusted, sourced Bash configuration files.
- Installation wipes the selected disk. Use the QEMU harness for destructive validation, never a host disk.
- The VM ISO is pinned in `vm/common.sh`; installed package versions follow Void's rolling repositories.

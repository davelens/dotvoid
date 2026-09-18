# Domain glossary

Terms used across scripts, docs, and reviews. Modules are named after them.

- **Machine profile** — a sourced Bash `.env` file describing one target
  machine (disk, identity, locale, libc, filesystem layout, packages,
  services). May layer over another profile by sourcing it. Loaded, validated
  and resolved by `scripts/install-profile.sh`.
- **Safety check** — the pre-wipe inspection of the live system that refuses
  partitions, mounted disks and an occupied `/mnt`. `scripts/install-safety.sh`.
- **Live ISO** — the official Void live image the installer runs from.
  Pinned for the harness in `vm/common.sh`.
- **Chroot configuration** — the second half of the install, run inside the
  bootstrapped target by `scripts/configure.sh`; receives the resolved profile
  and secrets as files under `/root`.
- **QEMU harness** — the host-side scripts under `vm/` that boot the live ISO,
  drive an unattended install over the serial console, and boot the result.
- **dotsys** — the separate repository that provisions the desktop after a
  base install; nothing personalised belongs here.

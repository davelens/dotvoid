# dotvoid

Deterministic Void Linux installation and configuration.

Instead of clicking through `void-installer`, the entire install is a
versioned, replayable pipeline: a config file describes the machine, a
script performs the install from the official live ISO, and a QEMU
harness lets you test the whole thing end-to-end before touching real
hardware.

Choices baked in:

- **glibc** — Steam and Discord are proprietary glibc binaries; musl
  would force Flatpak workarounds for both. (`LIBC` is still a config
  variable if you ever want a musl box.)
- **UEFI + GRUB** — with the `--removable` fallback path so it boots
  even on firmware that ignores efivars.
- **btrfs** — subvolumes `@` (/), `@home`, `@snapshots`, mounted with
  `compress=zstd,noatime`.

## Layout

```
config/
  default.env      # real hardware profile (edit DISK before use!)
  vm.env           # QEMU test profile, fully non-interactive
scripts/
  install.sh       # run from the live ISO: partition, bootstrap, chroot
  configure.sh     # runs inside the chroot (invoked by install.sh)
  post.sh          # on the booted system: updates, Steam, Discord, extras
vm/
  fetch-iso.sh     # download + sha256-verify the live ISO
  run.sh           # boot live ISO + fresh disk in QEMU (UEFI, 9p share)
  test.sh          # boot the installed disk to verify it works
  common.sh        # shared settings (ISO version, disk size, OVMF paths)
```

## Testing in a VM

Host requirements: `qemu-system-x86_64`, `edk2-ovmf`, KVM.

```sh
./vm/fetch-iso.sh    # download + verify the live ISO
./vm/run.sh          # boots the live ISO with the repo shared via 9p
```

Inside the VM (login `root` / `voidlinux`):

```sh
mkdir -p /media/repo
mount -t 9p -o trans=virtio,version=9p2000.L repo /media/repo
FORCE=1 /media/repo/scripts/install.sh /media/repo/config/vm.env
poweroff
```

Then verify the installed system boots on its own:

```sh
./vm/test.sh         # also forwards ssh to localhost:2222
```

Use `./vm/run.sh --fresh` to wipe the disk and start over.

## Installing on real hardware

1. Copy `config/default.env`, set `DISK` (use `/dev/disk/by-id/...`),
   hostname, user, timezone. Leave passwords empty to be prompted.
2. Boot the official Void live ISO (x86_64, glibc, base).
3. Get this repo onto the live system (git clone, USB stick, curl).
4. Run:

   ```sh
   sudo ./scripts/install.sh config/my-machine.env
   ```

5. Reboot into the new system, then finish up:

   ```sh
   sudo ./scripts/post.sh config/my-machine.env
   ```

`post.sh` is re-runnable: it updates the system, installs
`POST_PACKAGES`, enables nonfree/multilib repos + Steam, and installs
Discord via Flatpak (per the `ENABLE_*` flags in the config).

## Desktop (sway)

The sway desktop bootstrap lives in the dotsys repo
(`~/Repositories/davelens/dotsys/void/init.sh`), mirroring its Arch
setup. Since Void has no systemd, the session stack differs:

| Arch (dotsys/arch) | Void (dotsys/void) |
|---|---|
| uwsm session | greetd runs `sway-session` wrapper |
| logind sessions | turnstile (`turnstiled` + `pam_turnstile`) |
| logind seats | seatd |
| systemd user units | turnstile runit services in `~/.config/service/` |
| `dbus-run-session` | turnstile dbus user service (shared bus) |

After a base install + `post.sh`, clone dotsys and run
`void/init.sh` as your user.

## Notes

- `install.sh` wipes the target disk entirely. It refuses to run
  without an interactive `yes` or `FORCE=1`.
- The live ISO version used by the VM harness is pinned in
  `vm/common.sh` (`VOID_VERSION`).
- Void is a rolling release: "deterministic" here means the *procedure
  and configuration* are reproducible; package versions move with the
  repos.

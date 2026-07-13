# dotvoid

Deterministic Void Linux installation and configuration.

Instead of clicking through `void-installer`, the entire install is a
versioned, replayable pipeline: a config file describes the machine, a
script performs the install from the official live ISO, and a QEMU
harness lets you test the whole thing end-to-end before touching real
hardware.

Choices baked in:

- **glibc** — the personalized dotsys profile installs native Steam and
  targets x86_64 glibc. (`LIBC` is still a config variable if you want a
  minimal musl base system without that profile.)
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
./vm/install.sh      # fresh disk + fully unattended install
```

The command logs into the live image, mounts the repository, runs the
installer, and powers off automatically. Then verify the installed system:

```sh
./vm/test.sh         # also forwards ssh to localhost:2222
```

For manual debugging, boot the live image in a graphical QEMU window:

```sh
./vm/run.sh --fresh
```

## Installing on real hardware

1. Copy `config/default.env`, set `DISK` (use `/dev/disk/by-id/...`),
   hostname, user, timezone. Leave passwords empty to be prompted.
2. Boot the official Void live ISO (x86_64, glibc, base).
3. Get this repo onto the live system (git clone, USB stick, curl).
4. Run:

   ```sh
   sudo ./scripts/install.sh config/my-machine.env
   ```

5. Reboot into the new system.
6. Clone [dotsys](https://github.com/davelens/dotsys) and run its Void
   bootstrap as your desktop user:

   ```sh
   git clone https://github.com/davelens/dotsys \
     ~/Repositories/davelens/dotsys
   ~/Repositories/davelens/dotsys/void/init.sh
   ```

Personalized packages and applications are intentionally provisioned by
`dotsys`, not by this base-system installer.

## Desktop (sway)

The sway desktop bootstrap lives in the dotsys repo
(`~/Repositories/davelens/dotsys/void/init.sh`), mirroring its Arch
setup. Since Void has no systemd, the session stack differs:

| Arch (dotsys/arch) | Void (dotsys/void) |
|---|---|
| uwsm session | greetd runs `sway-session` wrapper |
| systemd-logind | elogind (sessions, seats, power, polkit identity) |
| systemd user units | turnstile runit services in `~/.config/service/` |
| `dbus-run-session` | turnstile dbus user service (shared bus) |

Turnstile remains the user-service supervisor but is configured with
`manage_rundir = no`; elogind owns `XDG_RUNTIME_DIR`. Graphical services are
launched through Sway while turnstile supervises their lifetime, keeping them
in the active elogind session required for graphical polkit authentication.

After a base install, clone dotsys and run `void/init.sh` as your user.

## Notes

- `install.sh` wipes the target disk entirely. It refuses to run
  without an interactive `yes` or `FORCE=1`.
- The live ISO version used by the VM harness is pinned in
  `vm/common.sh` (`VOID_VERSION`).
- Void is a rolling release: "deterministic" here means the *procedure
  and configuration* are reproducible; package versions move with the
  repos.

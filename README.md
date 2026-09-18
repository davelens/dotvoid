# dotvoid

A config-driven Void Linux base-system installer and a QEMU harness for
testing it end-to-end. On real hardware, run `scripts/install.sh` from
the official live ISO. On a host, `vm/install.sh` creates a VM disk and
drives that same installer unattended; desktop provisioning remains in
the separate dotsys repository.

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
  vm.env           # QEMU test profile; layers over default.env
scripts/
  install.sh       # run from the live ISO: partition, bootstrap, chroot
  install-profile.sh # load + validate a machine profile, derive settings
  install-safety.sh  # refuse partitions, mounted disks, occupied /mnt
  configure.sh     # runs inside the chroot (invoked by install.sh)
vm/
  fetch-iso.sh     # download + sha256-verify the live ISO
  install.sh       # create a fresh disk and run an unattended VM install
  auto-install.py  # drive the serial-console install and validate completion
  run.sh           # boot live ISO + fresh disk in QEMU (UEFI, 9p share)
  test.sh          # boot the installed disk for manual verification
  common.sh        # harness: settings, qemu argv per mode, disk + kernel helpers
```

## Host-only checks

These checks use fake guests and mocked disk inspection; they do not boot
QEMU or touch real disks:

```sh
python3 vm/test-auto-install.py
bash vm/test-host.sh
```

## Testing in a VM

Host requirements: `curl`, `sha256sum`, `qemu-system-x86_64`, `qemu-img`,
working KVM access, OVMF firmware, `bsdtar`, and Python 3. `run.sh` and
`test.sh` also need QEMU's GTK display and virtio GPU. Arch splits these
into separate packages:

```sh
sudo pacman -S qemu-system-x86 qemu-img edk2-ovmf \
  qemu-ui-gtk qemu-hw-display-virtio-gpu qemu-hw-display-virtio-vga
```

```sh
./vm/install.sh      # fresh disk + fully unattended install
```

The live ISO is downloaded and verified on first use (`vm/fetch-iso.sh`
also runs standalone to re-verify a cached ISO).

`vm/install.sh` logs into the live image over its serial console, mounts
the repository, runs the installer, and validates its completion before
the VM powers off. `vm/test.sh` then boots only the installed disk for
manual verification (including login and UEFI boot):

```sh
./vm/test.sh         # also forwards ssh to localhost:2222
```

For manual debugging, boot the live image in a graphical QEMU window:

```sh
./vm/run.sh --fresh
```

## Installing on real hardware

1. Copy `config/default.env`, set `DISK` (use `/dev/disk/by-id/...`),
   hostname, user, timezone. Leave passwords empty to be prompted. A
   profile may also source `default.env` and override only what differs,
   as `config/vm.env` does.
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
  without an interactive `yes` or `FORCE=1`. It also rejects partition
  targets, mounted disks (including descendants/swap), and an occupied
  `/mnt` mount tree; `FORCE=1` does not bypass those checks.
- The live ISO version used by the VM harness is pinned in
  `vm/common.sh` (`VOID_VERSION`). `STATE_DIR`, `OVMF_CODE` and
  `OVMF_VARS_TEMPLATE` can be preset in the environment to relocate
  harness state or point at non-standard firmware paths.
- Void is a rolling release: "deterministic" here means the *procedure
  and configuration* are reproducible; package versions move with the
  repos.

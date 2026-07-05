#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
# configure.sh — runs INSIDE the chroot, invoked by install.sh.
#
# Expects /root/install.env (the config) and /root/install.secrets
# (ROOT_PASSWORD / USER_PASSWORD) to exist; install.sh puts them there.
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

log() { printf '\033[1;34m  ->\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# shellcheck source=/dev/null
. /root/install.env
# shellcheck source=/dev/null
. /root/install.secrets

# ── Identity ─────────────────────────────────────────────────────────

log "hostname: $HOSTNAME"
echo "$HOSTNAME" > /etc/hostname

# ── Locale / time / keymap ───────────────────────────────────────────

log "timezone: $TIMEZONE, keymap: $KEYMAP"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
sed -i "s/^#\?KEYMAP=.*/KEYMAP=$KEYMAP/" /etc/rc.conf

if [ "$LIBC" = "glibc" ]; then
  log "locale: $LOCALE"
  echo "LANG=$LOCALE" > /etc/locale.conf
  sed -i "s/^#\($LOCALE.*\)/\1/" /etc/default/libc-locales
  xbps-reconfigure -f glibc-locales
fi

# ── Users ────────────────────────────────────────────────────────────

log "root password + user: $USERNAME"
# -c SHA512 makes chpasswd hash + write /etc/shadow itself, bypassing PAM.
# Void's /etc/pam.d/chpasswd has pam_permit.so in the password stack, so
# PAM-mode chpasswd exits 0 WITHOUT setting anything.
echo "root:$ROOT_PASSWORD" | chpasswd -c SHA512

if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -G "$USER_GROUPS" -s /bin/bash "$USERNAME"
fi
echo "$USERNAME:$USER_PASSWORD" | chpasswd -c SHA512

# Verify the hashes actually landed in /etc/shadow (see PAM note above).
for u in root "$USERNAME"; do
  awk -F: -v u="$u" '$1 == u && $2 ~ /^\$/ { found = 1 } END { exit !found }' \
    /etc/shadow || die "password for '$u' was not written to /etc/shadow"
done

# Sudo for wheel (base-system ships sudo).
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# ── Bootloader ───────────────────────────────────────────────────────

log "installing GRUB (UEFI)"
# --removable writes the fallback path BOOTX64.EFI; this boots even when
# efivars aren't writable (some VMs/firmware), so it's the one that must
# succeed. The NVRAM entry is best-effort on top.
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
  --removable --recheck
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
  --bootloader-id=Void --recheck \
  || log "NVRAM boot entry failed (read-only efivars?); fallback path installed"
grub-mkconfig -o /boot/grub/grub.cfg

# ── Services (runit) ─────────────────────────────────────────────────

for svc in $SERVICES; do
  [ -d "/etc/sv/$svc" ] || die "unknown service: $svc"
  log "enabling service: $svc"
  ln -sf "/etc/sv/$svc" /etc/runit/runsvdir/default/
done

# base-system enables dhcpcd + wpa_supplicant by default; they fight
# with NetworkManager, so disable them when NM is in the service list.
case " $SERVICES " in
  *" NetworkManager "*)
    rm -f /etc/runit/runsvdir/default/dhcpcd
    rm -f /etc/runit/runsvdir/default/wpa_supplicant
    ;;
esac

# ── Finalize ─────────────────────────────────────────────────────────

log "regenerating initramfs + reconfiguring packages"
xbps-reconfigure -fa

log "chroot configuration complete"

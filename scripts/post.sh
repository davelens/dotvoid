#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
# post.sh — post-install setup on the BOOTED system. Re-runnable.
#
#   sudo ./scripts/post.sh config/default.env
#
# Handles everything that doesn't belong in the base install: extra
# packages, nonfree/multilib repos, Steam, Discord (Flatpak).
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

CONFIG="${1:-}"
[ -n "$CONFIG" ] || die "usage: $0 <config.env>"
[ -f "$CONFIG" ] || die "config not found: $CONFIG"
# shellcheck source=/dev/null
. "$CONFIG"

[ "$(id -u)" -eq 0 ] || die "must run as root (sudo)"

log "Syncing repos + updating system"
xbps-install -Syu xbps
xbps-install -yu

if [ -n "${POST_PACKAGES:-}" ]; then
  log "Installing extra packages: $POST_PACKAGES"
  # shellcheck disable=SC2086
  xbps-install -Sy $POST_PACKAGES
fi

# ── Steam (needs nonfree + 32-bit multilib; glibc only) ─────────────

if [ "${ENABLE_STEAM:-no}" = "yes" ]; then
  [ "$LIBC" = "glibc" ] || die "Steam requires glibc"
  log "Enabling nonfree + multilib repos, installing Steam"
  xbps-install -Sy void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree
  xbps-install -Sy steam
fi

# ── Discord via Flatpak ──────────────────────────────────────────────

if [ "${ENABLE_DISCORD_FLATPAK:-no}" = "yes" ]; then
  log "Installing Discord (Flatpak)"
  xbps-install -Sy flatpak
  flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install -y --noninteractive flathub com.discordapp.Discord
fi

log "Post-install complete."

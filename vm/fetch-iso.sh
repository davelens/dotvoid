#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
# fetch-iso.sh — download the Void live ISO and verify its sha256.
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

# shellcheck source=vm/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mkdir -p "$STATE_DIR"

MANIFEST_PATH="$STATE_DIR/sha256sum.txt"

log "Fetching checksums"
curl -fsSL -o "$MANIFEST_PATH.part" "$VOID_MIRROR/sha256sum.txt"
mv "$MANIFEST_PATH.part" "$MANIFEST_PATH"

if [ -f "$ISO_PATH" ]; then
  log "Verifying cached ISO"
  verify_iso "$MANIFEST_PATH" "$ISO_PATH" || \
    die "cached ISO failed checksum verification: $ISO_PATH"
else
  log "Downloading $ISO_NAME"
  curl -fL --progress-bar -o "$ISO_PATH.part" "$VOID_MIRROR/$ISO_NAME"

  log "Verifying downloaded ISO"
  verify_iso "$MANIFEST_PATH" "$ISO_PATH.part" || \
    die "downloaded ISO failed checksum verification: $ISO_PATH.part"
  mv "$ISO_PATH.part" "$ISO_PATH"
fi

log "OK: $ISO_PATH"

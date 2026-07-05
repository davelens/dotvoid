#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
# fetch-iso.sh — download the Void live ISO and verify its sha256.
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

# shellcheck source=vm/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mkdir -p "$STATE_DIR"

if [ -f "$ISO_PATH" ]; then
  log "ISO already present: $ISO_PATH"
else
  log "Downloading $ISO_NAME"
  curl -fL --progress-bar -o "$ISO_PATH.part" "$VOID_MIRROR/$ISO_NAME"
  mv "$ISO_PATH.part" "$ISO_PATH"
fi

log "Fetching checksums"
curl -fsSL -o "$STATE_DIR/sha256sum.txt" "$VOID_MIRROR/sha256sum.txt"

log "Verifying"
(cd "$STATE_DIR" && sha256sum -c --ignore-missing sha256sum.txt)

log "OK: $ISO_PATH"

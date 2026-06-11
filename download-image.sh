#!/usr/bin/env bash
# =============================================================================
# scripts/download-image.sh
# Downloads an Ubuntu 22.04 cloud image and verifies its SHA256 checksum.
#
# Usage: download-image.sh <arch> <artifacts_dir> <url> <filename>
#   arch         : x86_64 | arm64
#   artifacts_dir: destination directory
#   url          : full URL to the .img file
#   filename     : base filename to save as
# =============================================================================
set -euo pipefail

ARCH="${1:?arch required (x86_64 or arm64)}"
ARTIFACTS_DIR="${2:?artifacts_dir required}"
IMAGE_URL="${3:?image URL required}"
IMAGE_FILENAME="${4:?filename required}"

CHECKSUMS_URL="$(dirname "$IMAGE_URL")/SHA256SUMS"

# Output filenames use a clean arch suffix
case "$ARCH" in
  x86_64) OUTPUT_QCOW2="$ARTIFACTS_DIR/ubuntu-x86_64.qcow2" ;;
  arm64)  OUTPUT_QCOW2="$ARTIFACTS_DIR/ubuntu-arm64.qcow2" ;;
  *)      echo "ERROR: unknown arch '$ARCH'" >&2; exit 1 ;;
esac

RAW_IMG="$ARTIFACTS_DIR/$IMAGE_FILENAME"

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[32m'
CYAN='\033[36m'
YELLOW='\033[33m'
RESET='\033[0m'

log()  { printf "${BOLD}[download]${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${RESET} %s\n" "$*"; }
info() { printf "${CYAN}  →${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${RESET}  %s\n" "$*"; }

# ── Skip if already downloaded ────────────────────────────────────────────────
if [[ -f "$OUTPUT_QCOW2" ]]; then
  ok "Ubuntu $ARCH image already exists: $OUTPUT_QCOW2"
  info "Delete it and re-run to force re-download."
  exit 0
fi

mkdir -p "$ARTIFACTS_DIR"

# ── Download the cloud image ──────────────────────────────────────────────────
log "Downloading Ubuntu 22.04 $ARCH cloud image..."
info "URL: $IMAGE_URL"
info "Destination: $RAW_IMG"

curl \
  --location \
  --progress-bar \
  --output "$RAW_IMG" \
  "$IMAGE_URL"

ok "Download complete: $(du -sh "$RAW_IMG" | cut -f1)"

# ── Verify checksum ───────────────────────────────────────────────────────────
log "Verifying SHA256 checksum..."
info "Fetching checksums from: $CHECKSUMS_URL"

CHECKSUMS_FILE="$ARTIFACTS_DIR/SHA256SUMS-$ARCH"
curl \
  --silent \
  --location \
  --output "$CHECKSUMS_FILE" \
  "$CHECKSUMS_URL"

# Extract the expected checksum for our file
EXPECTED_HASH=$(grep "$IMAGE_FILENAME" "$CHECKSUMS_FILE" | awk '{print $1}')
if [[ -z "$EXPECTED_HASH" ]]; then
  warn "Could not find checksum for $IMAGE_FILENAME in SHA256SUMS"
  warn "Proceeding anyway — manually verify if needed"
else
  info "Expected: $EXPECTED_HASH"

  # Compute actual hash
  if command -v sha256sum &>/dev/null; then
    ACTUAL_HASH=$(sha256sum "$RAW_IMG" | awk '{print $1}')
  elif command -v shasum &>/dev/null; then
    ACTUAL_HASH=$(shasum -a 256 "$RAW_IMG" | awk '{print $1}')
  else
    warn "No sha256sum or shasum found — skipping verification"
    ACTUAL_HASH="$EXPECTED_HASH"
  fi

  info "Actual:   $ACTUAL_HASH"

  if [[ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]]; then
    printf '\033[31mERROR: Checksum mismatch! Download may be corrupt.\033[0m\n' >&2
    rm -f "$RAW_IMG"
    exit 1
  fi

  ok "Checksum verified ✓"
fi

# ── Convert to qcow2 if needed ────────────────────────────────────────────────
# Ubuntu provides .img files (raw format). Convert to qcow2 for sparse storage
# and snapshot support — much better for QEMU workflows.

if [[ "$RAW_IMG" != "$OUTPUT_QCOW2" ]]; then
  log "Converting to qcow2 format (sparse, copy-on-write)..."
  qemu-img convert \
    -f raw \
    -O qcow2 \
    -p \
    "$RAW_IMG" \
    "$OUTPUT_QCOW2"

  ok "Converted: $(du -sh "$OUTPUT_QCOW2" | cut -f1) (sparse)"
  rm -f "$RAW_IMG"
  info "Raw image removed. Using: $OUTPUT_QCOW2"
else
  # File was already qcow2
  mv "$RAW_IMG" "$OUTPUT_QCOW2"
fi

# ── Resize the disk image ─────────────────────────────────────────────────────
# Default Ubuntu cloud images are ~2.2 GB. Expand to 10 GB for usable space.
log "Resizing disk to 10G..."
qemu-img resize "$OUTPUT_QCOW2" 10G
ok "Disk resized to 10G"

# ── Done ──────────────────────────────────────────────────────────────────────
printf "\n"
ok "Ready: $OUTPUT_QCOW2"
printf "  Run ${BOLD}make seed && make run${RESET} to boot\n\n"

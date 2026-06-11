#!/usr/bin/env bash
# =============================================================================
# scripts/make-seed.sh
# Builds a cloud-init "seed" ISO used to configure the Ubuntu guest on boot.
#
# The seed ISO contains two files:
#   user-data  — SSH credentials, packages, first-boot commands
#   meta-data  — instance ID and hostname
#
# QEMU mounts this as a virtual CD-ROM. Cloud-init reads it on first boot.
#
# Usage: make-seed.sh <artifacts_dir>
# =============================================================================
set -euo pipefail

ARTIFACTS_DIR="${1:?artifacts_dir required}"
SEED_ISO="$ARTIFACTS_DIR/seed.iso"
CLOUD_INIT_DIR="$(dirname "$0")/cloud-init"

BOLD='\033[1m'
GREEN='\033[32m'
CYAN='\033[36m'
RESET='\033[0m'

log()  { printf "${BOLD}[seed]${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${RESET} %s\n" "$*"; }
info() { printf "${CYAN}  →${RESET} %s\n" "$*"; }

mkdir -p "$ARTIFACTS_DIR"

log "Building cloud-init seed ISO..."
info "Source: $CLOUD_INIT_DIR"
info "Output: $SEED_ISO"

# ── Verify cloud-init source files exist ─────────────────────────────────────
if [[ ! -f "$CLOUD_INIT_DIR/user-data" ]]; then
  echo "ERROR: $CLOUD_INIT_DIR/user-data not found" >&2
  exit 1
fi
if [[ ! -f "$CLOUD_INIT_DIR/meta-data" ]]; then
  echo "ERROR: $CLOUD_INIT_DIR/meta-data not found" >&2
  exit 1
fi

# ── Build the ISO ─────────────────────────────────────────────────────────────
# cloud-localds is the preferred tool (from cloud-image-utils)
# Fallback to genisoimage if not available

if command -v cloud-localds &>/dev/null; then
  info "Using cloud-localds"
  cloud-localds \
    "$SEED_ISO" \
    "$CLOUD_INIT_DIR/user-data" \
    "$CLOUD_INIT_DIR/meta-data"

elif command -v genisoimage &>/dev/null; then
  info "Using genisoimage (cloud-localds not found)"
  TMPDIR=$(mktemp -d)
  cp "$CLOUD_INIT_DIR/user-data" "$TMPDIR/"
  cp "$CLOUD_INIT_DIR/meta-data" "$TMPDIR/"
  genisoimage \
    -output "$SEED_ISO" \
    -volid cidata \
    -joliet \
    -rock \
    "$TMPDIR"
  rm -rf "$TMPDIR"

elif command -v mkisofs &>/dev/null; then
  info "Using mkisofs (cloud-localds not found)"
  TMPDIR=$(mktemp -d)
  cp "$CLOUD_INIT_DIR/user-data" "$TMPDIR/"
  cp "$CLOUD_INIT_DIR/meta-data" "$TMPDIR/"
  mkisofs \
    -output "$SEED_ISO" \
    -volid cidata \
    -joliet \
    -rock \
    "$TMPDIR"
  rm -rf "$TMPDIR"

else
  echo "ERROR: No ISO builder found. Install cloud-image-utils or genisoimage." >&2
  exit 1
fi

ok "Seed ISO built: $(du -sh "$SEED_ISO" | cut -f1)"

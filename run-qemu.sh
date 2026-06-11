#!/usr/bin/env bash
# =============================================================================
# scripts/run-qemu.sh
# Launches a QEMU guest with the correct flags for x86_64 or ARM64.
# Runs inside the Docker container (or directly on host if QEMU is installed).
#
# Usage: run-qemu.sh [x86_64|arm64]
# =============================================================================
set -euo pipefail

ARCH="${1:-x86_64}"
ARTIFACTS_DIR="/artifacts"
HOST_SSH_PORT=2222

BOLD='\033[1m'
GREEN='\033[32m'
CYAN='\033[36m'
YELLOW='\033[33m'
RESET='\033[0m'

log()  { printf "${BOLD}[qemu]${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${RESET} %s\n" "$*"; }
info() { printf "${CYAN}  →${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${RESET}  %s\n" "$*"; }

# ── Validate artifacts ────────────────────────────────────────────────────────
DISK_IMAGE="$ARTIFACTS_DIR/ubuntu-$ARCH.qcow2"
SEED_ISO="$ARTIFACTS_DIR/seed.iso"
CONSOLE_LOG="$ARTIFACTS_DIR/console.log"

if [[ ! -f "$DISK_IMAGE" ]]; then
  echo "ERROR: Disk image not found: $DISK_IMAGE" >&2
  echo "Run: make download (x86_64) or make download-arm64" >&2
  exit 1
fi

if [[ ! -f "$SEED_ISO" ]]; then
  echo "ERROR: Cloud-init seed ISO not found: $SEED_ISO" >&2
  echo "Run: make seed" >&2
  exit 1
fi

# ── Detect acceleration ───────────────────────────────────────────────────────
detect_accel() {
  # Inside Docker on Linux with --device /dev/kvm passed
  if [[ -c /dev/kvm ]]; then
    echo "kvm"
  else
    echo "tcg"
  fi
}

ACCEL=$(detect_accel)

# ── Build QEMU command based on arch ─────────────────────────────────────────
case "$ARCH" in
  x86_64)
    QEMU_BIN="qemu-system-x86_64"
    MACHINE="q35"

    if [[ "$ACCEL" == "kvm" ]]; then
      ACCEL_FLAGS=(-enable-kvm -cpu host)
      warn_msg=""
    else
      ACCEL_FLAGS=(-accel tcg -cpu qemu64)
      warn_msg="KVM not available — using software emulation (slower)"
    fi

    QEMU_CMD=(
      "$QEMU_BIN"
        # Machine and acceleration
        -machine "$MACHINE"
        "${ACCEL_FLAGS[@]}"
        # Resources
        -m 2048
        -smp 2
        # Storage: main disk
        -drive "file=$DISK_IMAGE,format=qcow2,if=virtio,cache=writeback"
        # Storage: cloud-init seed ISO (virtual CD-ROM)
        -drive "file=$SEED_ISO,format=raw,if=virtio,media=cdrom,readonly=on"
        # Networking: user-mode with SSH port forward
        -netdev "user,id=net0,hostfwd=tcp::${HOST_SSH_PORT}-:22"
        -device "virtio-net-pci,netdev=net0"
        # Display: no GUI, serial console only
        -nographic
        # Serial: log to file AND show in stdout
        -serial "file:$CONSOLE_LOG"
    )
    ;;

  arm64|aarch64)
    QEMU_BIN="qemu-system-aarch64"
    MACHINE="virt"

    # ARM64 on x86 host always uses TCG software emulation
    # ARM64 on ARM64 host can use KVM or HVF
    if [[ "$ACCEL" == "kvm" ]] && [[ "$(uname -m)" == "aarch64" ]]; then
      ACCEL_FLAGS=(-enable-kvm -cpu host)
    else
      ACCEL_FLAGS=(-accel tcg -cpu cortex-a72)
      if [[ "$ACCEL" != "kvm" ]]; then
        warn_msg="ARM64 software emulation on x86 host — expect slow boot (5–15 min)"
      fi
    fi

    # ARM64 QEMU requires explicit BIOS firmware
    # Use the bundled AAVMF (ARM UEFI) firmware
    BIOS_CANDIDATES=(
      /usr/share/qemu-efi-aarch64/QEMU_EFI.fd
      /usr/share/edk2/aarch64/QEMU_EFI.fd
      /usr/local/share/qemu/edk2-aarch64-code.fd
    )
    BIOS_FILE=""
    for f in "${BIOS_CANDIDATES[@]}"; do
      if [[ -f "$f" ]]; then
        BIOS_FILE="$f"
        break
      fi
    done

    if [[ -z "$BIOS_FILE" ]]; then
      # Install aavmf if not present
      warn "AAVMF firmware not found — installing..."
      apt-get install -y --no-install-recommends qemu-efi-aarch64 2>/dev/null || true
      BIOS_FILE="/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
    fi

    QEMU_CMD=(
      "$QEMU_BIN"
        # Machine, firmware, acceleration
        -machine "$MACHINE,highmem=off"
        -bios "$BIOS_FILE"
        "${ACCEL_FLAGS[@]}"
        # Resources
        -m 2048
        -smp 2
        # Storage
        -drive "file=$DISK_IMAGE,format=qcow2,if=virtio,cache=writeback"
        -drive "file=$SEED_ISO,format=raw,if=virtio,media=cdrom,readonly=on"
        # Networking
        -netdev "user,id=net0,hostfwd=tcp::${HOST_SSH_PORT}-:22"
        -device "virtio-net-pci,netdev=net0"
        # Display
        -nographic
        -serial "file:$CONSOLE_LOG"
    )
    ;;

  *)
    echo "ERROR: Unsupported arch: $ARCH (use x86_64 or arm64)" >&2
    exit 1
    ;;
esac

# ── Print startup info ────────────────────────────────────────────────────────
log "Starting Ubuntu 22.04 guest ($ARCH)"
info "Disk image:  $DISK_IMAGE"
info "Seed ISO:    $SEED_ISO"
info "Console log: $CONSOLE_LOG"
info "SSH port:    localhost:$HOST_SSH_PORT"
info "Acceleration: $ACCEL"
[[ -n "${warn_msg:-}" ]] && warn "$warn_msg"
printf "\n"
info "QEMU command:"
printf "  %s\n\n" "${QEMU_CMD[*]}"

ok "Launching QEMU... (first boot: 60–120s, ARM64 software: 5–15 min)"
printf "  Serial output → $CONSOLE_LOG\n"
printf "  Run 'make logs' in another terminal to follow boot progress.\n\n"

# ── Execute ───────────────────────────────────────────────────────────────────
exec "${QEMU_CMD[@]}"

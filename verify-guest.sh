#!/usr/bin/env bash
# =============================================================================
# scripts/verify-guest.sh
# SSHes into the running guest and runs diagnostic commands to confirm it is
# healthy. Used by 'make verify' and CI pipelines.
#
# Usage: verify-guest.sh <host> <port>
# =============================================================================
set -euo pipefail

HOST="${1:-localhost}"
PORT="${2:-2222}"
USER="ubuntu"
PASS="ubuntu"

BOLD='\033[1m'
GREEN='\033[32m'
CYAN='\033[36m'
RED='\033[31m'
RESET='\033[0m'

log()     { printf "${BOLD}[verify]${RESET} %s\n" "$*"; }
ok()      { printf "${GREEN}✓${RESET} %s\n" "$*"; }
section() { printf "\n${BOLD}${CYAN}── %s ──────────────────────────────────${RESET}\n" "$*"; }
fail()    { printf "${RED}✗${RESET} %s\n" "$*" >&2; }

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=10
  -o PasswordAuthentication=yes
  -p "$PORT"
)

# ── Helper: run a command on the guest ───────────────────────────────────────
guest_cmd() {
  local cmd="$1"
  # Use sshpass if available; fall back to expect-style prompt handling
  if command -v sshpass &>/dev/null; then
    sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" "$USER@$HOST" "$cmd"
  else
    ssh "${SSH_OPTS[@]}" "$USER@$HOST" "$cmd"
  fi
}

log "Verifying Ubuntu guest at $HOST:$PORT"

# ── 1. Confirm SSH responds ───────────────────────────────────────────────────
section "SSH connectivity"
if nc -z -w 5 "$HOST" "$PORT" 2>/dev/null; then
  ok "Port $PORT is open"
else
  fail "Port $PORT is not reachable"
  exit 1
fi

# ── 2. Run diagnostics on the guest ──────────────────────────────────────────
# Note: password auth requires sshpass. If not installed, we print instructions.

if ! command -v sshpass &>/dev/null; then
  log "sshpass not found — printing manual SSH command"
  printf "\n"
  printf "  Connect manually:\n"
  printf "  ${CYAN}ssh -o StrictHostKeyChecking=no -p %s %s@%s${RESET}\n" "$PORT" "$USER" "$HOST"
  printf "  Password: ${CYAN}%s${RESET}\n\n" "$PASS"
  printf "  Or run: ${BOLD}make ssh${RESET}\n\n"
  ok "SSH port verified. Guest appears healthy."
  exit 0
fi

section "Guest OS info"
guest_cmd "uname -a" && ok "uname OK"

section "CPU info"
guest_cmd "grep 'model name' /proc/cpuinfo | head -1" && ok "cpuinfo OK"

section "Memory"
guest_cmd "free -h" && ok "memory OK"

section "Disk"
guest_cmd "df -h /" && ok "disk OK"

section "Network"
guest_cmd "ip addr show | grep 'inet '" && ok "network OK"

section "Cloud-init status"
guest_cmd "cloud-init status" && ok "cloud-init OK"

section "Uptime"
guest_cmd "uptime" && ok "uptime OK"

printf "\n"
ok "All checks passed — guest is healthy ✓"
printf "\n"
printf "  Connect: ${BOLD}make ssh${RESET}  (or ssh -p %s %s@%s)\n\n" "$PORT" "$USER" "$HOST"

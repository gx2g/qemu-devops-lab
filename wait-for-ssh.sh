#!/usr/bin/env bash
# =============================================================================
# scripts/wait-for-ssh.sh
# Polls an SSH port until it responds or a timeout is reached.
# Used by 'make verify' and GitHub Actions CI.
#
# Usage: wait-for-ssh.sh <host> <port> [timeout_seconds]
# =============================================================================
set -euo pipefail

HOST="${1:?host required}"
PORT="${2:?port required}"
TIMEOUT="${3:-180}"

BOLD='\033[1m'
GREEN='\033[32m'
CYAN='\033[36m'
RED='\033[31m'
RESET='\033[0m'

ELAPSED=0
INTERVAL=5

printf "${BOLD}Waiting for SSH on ${CYAN}%s:%s${RESET}${BOLD} (timeout: %ss)${RESET}\n" \
  "$HOST" "$PORT" "$TIMEOUT"

while true; do
  # Try to connect — nc exits 0 if port is open
  if nc -z -w 3 "$HOST" "$PORT" 2>/dev/null; then
    printf "\n${GREEN}✓ SSH port is open after %ss${RESET}\n" "$ELAPSED"
    exit 0
  fi

  if (( ELAPSED >= TIMEOUT )); then
    printf "\n${RED}✗ Timeout after %ss — SSH never became available${RESET}\n" "$TIMEOUT" >&2
    printf "  Check boot progress: make logs\n" >&2
    printf "  Check container:     docker logs qemu-guest\n" >&2
    exit 1
  fi

  # Progress indicator
  printf "  [%3ss] waiting...\r" "$ELAPSED"

  sleep "$INTERVAL"
  ELAPSED=$(( ELAPSED + INTERVAL ))
done

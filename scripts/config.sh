#!/usr/bin/env bash
# scripts/config.sh — view/edit the settings of an already-initialized
# node, without touching keys. For first-time setup (including key
# generation), use 'jocv init' instead.
#
# Scope for ROLE=validator (the currently-supported, guide-verified path):
# WITHDRAWAL_ADDRESS and BEACON_URL. NETWORK/ROLE are intentionally not
# editable here — see the warning this prints.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found. Run 'jocv init' first."
load_env
ROLE="${ROLE:-validator}"
NETWORK="${NETWORK:-mainnet}"

info "Current settings — NETWORK=$NETWORK, ROLE=$ROLE"
echo "  WITHDRAWAL_ADDRESS = ${WITHDRAWAL_ADDRESS:-<unset>}" >&2
echo "  BEACON_URL         = ${BEACON_URL:-<unset>}" >&2
echo >&2
warn "NETWORK and ROLE are not editable here — they're fixed at 'jocv init'"
warn "time because keys/deposit data are network-specific. Use a fresh"
warn "checkout for a different network or role."

if [[ "$ROLE" == "el-cl" ]]; then
  warn "ROLE=el-cl runs no Validator Client — WITHDRAWAL_ADDRESS/BEACON_URL"
  warn "don't apply. Execution/Consensus settings (EL_CLIENT_IMAGE,"
  warn "EL_NETWORK_ID, bootnodes) aren't covered by this command yet —"
  warn "edit $ENV_FILE directly for now."
  exit 0
fi

CHANGED=false

read -r -p "New withdrawal address (0x..., Enter to keep current): " new_addr
if [[ -n "$new_addr" ]]; then
  is_valid_eth_address "$new_addr" || die "Invalid address. Expected 0x + 40 hex characters."
  set_env_var "WITHDRAWAL_ADDRESS" "$new_addr"
  success "WITHDRAWAL_ADDRESS updated."
  CHANGED=true
fi

if [[ "$ROLE" == "all" ]]; then
  info "ROLE=all: BEACON_URL is auto-managed (points at the local 'beacon'"
  info "service) — not editable here. Use 'jocv beacon set' only if you"
  info "specifically want to override that."
else
  read -r -p "New beacon URL (Enter to keep current; guided version: 'jocv beacon set'): " new_beacon
  if [[ -n "$new_beacon" ]]; then
    is_valid_url "$new_beacon" || die "Invalid URL. Expected http(s)://host[:port][/path]."
    set_env_var "BEACON_URL" "$new_beacon"
    success "BEACON_URL updated."
    CHANGED=true
  fi
fi

if [[ "$CHANGED" == true ]]; then
  check_docker
  if confirm "Apply now via 'docker compose up -d'?"; then
    ( cd "$JOCV_ROOT" && docker compose up -d )
    success "Applied. Check with: jocv status"
  else
    info "Not applied yet — run 'jocv up' when ready."
  fi
else
  info "Nothing changed."
fi

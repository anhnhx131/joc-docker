#!/usr/bin/env bash
# scripts/beacon-set.sh — point the Validator Client at a Consensus Client /
# Beacon Node HTTP API.
#
# Only meaningful for ROLE=validator (guide Option 2: connects to an
# external Consensus Client, e.g. BCCloud). Used at two points in the
# guide, and deliberately shares the same mechanism for both:
#   - Step 2-7: first connection to the Consensus Client on BCCloud, after
#     Step 2-5 opens the Consensus HTTP API (e.g. http://<node-ip>:3500).
#   - Step 4-1: whenever the BCCloud endpoint needs to change as part of a
#     hard fork phase rollout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

BEACON_URL="${1:-}"
[[ -n "$BEACON_URL" ]] || die "Usage: jocv beacon set <url>   (e.g. http://<bccloud-node-ip>:3500)"
is_valid_url "$BEACON_URL" || die "Invalid URL: '$BEACON_URL' (expected http(s)://host[:port][/path])"

[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found. Run 'jocv init' first."
load_env

case "${ROLE:-validator}" in
  el-cl)
    die "ROLE=el-cl runs no Validator Client — there is nothing to point at a beacon URL for."
    ;;
  all)
    warn "ROLE=all: BEACON_URL is normally auto-managed to point at the local"
    warn "'beacon' service (http://beacon:5052). Overriding it here means your"
    warn "Validator Client will stop talking to your own beacon node."
    confirm "Set BEACON_URL to '$BEACON_URL' anyway?" || die "Aborted. Nothing was changed."
    ;;
esac

set_env_var "BEACON_URL" "$BEACON_URL"
success "BEACON_URL set to $BEACON_URL in $ENV_FILE"

check_docker
info "Applying via docker compose up -d (recreates the validator container with the new value)..."
( cd "$JOCV_ROOT" && docker compose up -d )
success "Done. Check status with: jocv status"

#!/usr/bin/env bash
# scripts/reset.sh — stop and remove this node's docker resources, and
# optionally wipe its data (keys, deposit data, execution/consensus chain
# data) and .env.
#
# Two tiers, on purpose:
#   jocv reset          -> stop + remove containers only. Reversible:
#                          data/ and .env are untouched, so 'jocv up' (or
#                          'jocv init') brings the node back as it was.
#   jocv reset --data   -> ALSO deletes data/ and .env. NOT reversible —
#                          the mnemonic-derived keystore and any submitted
#                          deposit data are gone for good. Requires a
#                          separate, explicit confirmation on top of the
#                          usual one.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

WIPE_DATA=false
case "${1:-}" in
  --data | --all) WIPE_DATA=true ;;
  "") ;;
  *) die "Usage: jocv reset [--data]" ;;
esac

check_docker

info "Stopping and removing containers for this node..."
( cd "$JOCV_ROOT" && docker compose down --remove-orphans )
success "Containers removed."

if [[ "$WIPE_DATA" != true ]]; then
  info "data/ and .env were left untouched."
  info "Bring the node back with: jocv up  (or 'jocv init' if .env is gone)"
  info "To also permanently delete keys/deposit data/.env: jocv reset --data"
  exit 0
fi

echo >&2
shout "=================================================================="
shout " 'jocv reset --data' will PERMANENTLY DELETE:"
[[ -d "$KEYS_DIR" ]] && shout "   - $KEYS_DIR"
shout "     (mnemonic-derived keystore, deposit_data-*.json, password.txt)"
[[ -d "$DATA_DIR" ]] && shout "   - all of $DATA_DIR (execution/consensus chain data, jwt.hex)"
[[ -f "$ENV_FILE" ]] && shout "   - $ENV_FILE (network/role/withdrawal address settings)"
shout ""
shout " If deposit_data-*.json was already submitted to Launchpad for this"
shout " validator, deleting its keystore/mnemonic means you can NEVER"
shout " operate that validator again. There is no undo, and no backup is"
shout " made — networks/ (public config) is untouched, but everything"
shout " under data/ and .env is gone."
shout "=================================================================="

confirm "Are you certain this validator's deposit (if any) is fully decommissioned, or was never submitted?" \
  || die "Aborted. Nothing was deleted."

confirm_strict "Permanently delete $DATA_DIR and $ENV_FILE?" "delete" \
  || die "Confirmation text did not match. Aborted. Nothing was deleted."

rm -rf "$DATA_DIR" "$ENV_FILE"
success "Removed $DATA_DIR and $ENV_FILE. Run 'jocv init' to start fresh."

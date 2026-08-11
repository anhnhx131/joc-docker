#!/usr/bin/env bash
# scripts/update-config.sh — Guide Step 4: apply a new hard fork phase's
# consensus config to an already-running node.
#
# Config source (checked in this order), for the network in .env:
#   1. networks/<NETWORK>/cl/phases/<phase>/config.yaml — phase-specific
#      file, meant to be committed to this repo by whoever maintains it
#      (see networks/README.md).
#   2. networks/<NETWORK>/cl/config.yaml                 — generic fallback.
#
# Applied in place at networks/<NETWORK>/cl/config.yaml, which is what the
# beacon/validator containers have bind-mounted as --testnet-dir — no copy
# into a separate data/ directory needed.
#
# This script never runs `git pull` itself and never fetches a config over
# the network on its own — pulling in a new consensus config is a
# human-reviewed action (it directly controls what chain your node
# follows), not something to automate silently.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

PHASE="${1:-}"
[[ -n "$PHASE" ]] || die "Usage: jocv update-config <phase-label>   (e.g. tokyo-phase-2)"

[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found. Run 'jocv init' first."
load_env
NETWORK="${NETWORK:-}"
is_supported_network "$NETWORK" || die "$ENV_FILE has no valid NETWORK set. Run 'jocv init' first."
ROLE="${ROLE:-validator}"

shout "=================================================================="
shout " Only run this AFTER an official announcement from JBF / admin."
shout " Do not update the config or restart the node on your own"
shout " initiative (guide, Step 4-1 Note)."
shout "=================================================================="

if [[ -d "$JOCV_ROOT/.git" ]] && command -v git >/dev/null 2>&1; then
  info "Repo state: $(git -C "$JOCV_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown) on $(git -C "$JOCV_ROOT" branch --show-current 2>/dev/null || echo unknown)"
  info "If your team commits phase configs to this repo, make sure you've"
  info "run 'git pull' and reviewed the diff before continuing."
fi

confirm "Has JBF / admin officially announced phase '$PHASE' for network '$NETWORK'?" || die "Aborted."

check_docker

CL_DIR="$(network_cl_dir "$NETWORK")"
PHASE_CONFIG="$(network_phases_dir "$NETWORK")/$PHASE/config.yaml"
FALLBACK_CONFIG="$CL_DIR/config.yaml"

if [[ -f "$PHASE_CONFIG" ]]; then
  NEW_CONFIG="$PHASE_CONFIG"
  info "Using phase-specific config: $NEW_CONFIG"
elif [[ -f "$FALLBACK_CONFIG" ]]; then
  NEW_CONFIG="$FALLBACK_CONFIG"
  warn "No phase-specific file at $PHASE_CONFIG."
  warn "Falling back to $FALLBACK_CONFIG — make sure this is really the"
  warn "config for phase '$PHASE' and not a stale/unrelated one."
else
  cat >&2 <<EOF

No config found for phase '$PHASE' on network '$NETWORK'. Expected one of:
  $PHASE_CONFIG
  $FALLBACK_CONFIG

If your team version-controls configs in this repo:
  1. git pull
  2. Confirm the file above now exists.

Otherwise, get it from JBF/admin (Step 4-1, item 3) and place it at one of
the paths above.

Then re-run: jocv update-config $PHASE
EOF
  die "Config not found for phase '$PHASE'."
fi

CHECKSUM="$(sha256_of "$NEW_CONFIG")"
echo >&2
info "About to apply: $NEW_CONFIG"
info "SHA-256: $CHECKSUM"
shout "Verify this checksum/file matches the official config for phase '$PHASE'"
shout "(the JOC page, or whatever JBF shared) BEFORE confirming below."
confirm "Confirmed this config is correct for phase '$PHASE' and safe to apply?" \
  || die "Aborted — verify the config against the official source, then retry."

if [[ -f "$FALLBACK_CONFIG" && "$NEW_CONFIG" != "$FALLBACK_CONFIG" ]]; then
  cp "$FALLBACK_CONFIG" "$CL_DIR/config.yaml.bak.$PHASE"
  info "Backed up previous config to config.yaml.bak.$PHASE"
fi
cp "$NEW_CONFIG" "$CL_DIR/config.yaml"
success "Updated $CL_DIR/config.yaml for phase '$PHASE'."

# Restart whichever containers actually read this config, based on ROLE.
RESTART_TARGETS=()
[[ "$ROLE" == "validator" || "$ROLE" == "all" ]] && RESTART_TARGETS+=("validator")
[[ "$ROLE" == "el-cl" || "$ROLE" == "all" ]] && RESTART_TARGETS+=("beacon")

info "Restarting: ${RESTART_TARGETS[*]} (docker compose restart)..."
( cd "$JOCV_ROOT" && docker compose restart "${RESTART_TARGETS[@]}" )
success "Done. Check with: jocv status"

warn "Per the guide: after 5-10 minutes, if 'Not attesting' keeps appearing for"
warn "more than 15-20 minutes, the validator is not operating properly."
warn "Also check the logs for critical errors (Step 4-1, Note)."

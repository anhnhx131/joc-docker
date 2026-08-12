#!/usr/bin/env bash
# staking-deposit-cli/import-entrypoint.sh — guide Step 2-6.
#
# Runs INSIDE the sigp/lighthouse container, as that container's entrypoint
# (overridden by staking-deposit-cli.yml's `validator-import` service; bind-mounted
# read-only, the published image itself is never rebuilt/modified). Same
# "compose file + bind-mounted entrypoint script" structure as
# generate-entrypoint.sh — see that file's header for the eth-docker
# reference this follows.
#
# NOT the same mechanism as eth-docker's own key import (its `validator-keys`
# service / keymanager.sh —
# https://github.com/ethstaker/eth-docker/blob/main/vc-utils/keymanager.sh):
# that imports into an ALREADY RUNNING validator client over its Keymanager REST
# API, which the JOC guide does not document and which no client in this
# project currently exposes. This stays the guide's Step 2-6 command —
# `lighthouse account_manager validator import`, an OFFLINE import straight
# into the datadir before the Validator Client ever starts. What this file
# *does* borrow from eth-docker is the structural pattern (a "tools"-profile
# compose service + dedicated entrypoint script) and the chown-back-to-host
# convention (see HOST_UID/HOST_GID below).
#
# Env vars, set by staking-deposit-cli.yml (ultimately from jocv / a human):
#   HOST_UID / HOST_GID  optional, default 0:0 (root) — see chown_back().
set -euo pipefail

COLOR_RED=$'\033[31m'
COLOR_GREEN=$'\033[32m'
COLOR_RESET=$'\033[0m'
info()    { printf '%s\n' "[INFO] $*" >&2; }
success() { printf '%s[OK]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*" >&2; }
error()   { printf '%s[ERROR]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2; }
die()     { error "$*"; exit 1; }

DATADIR=/data
KEYS_DIR="$DATADIR/validator_keys"
TESTNET_DIR="$DATADIR/config"
HOST_UID="${HOST_UID:-0}"
HOST_GID="${HOST_GID:-0}"

chown_back() {
  chown -R "$HOST_UID:$HOST_GID" "$DATADIR/validators" 2>/dev/null || true
}

[[ -f "$KEYS_DIR/password.txt" ]] \
  || die "$KEYS_DIR/password.txt not found. Run 'docker compose -f staking-deposit-cli.yml run --rm deposit-generate' first."
[[ -d "$TESTNET_DIR" ]] \
  || die "$TESTNET_DIR not found — is networks/<NETWORK>/cl mounted (staking-deposit-cli.yml's NETWORK var)?"

info "Importing the validator key into the Lighthouse Validator Client (guide Step 2-6)..."
# --- BEGIN: adapted from guide, Step 2-6 (an extra volume mount, set up by
#     staking-deposit-cli.yml, so --testnet-dir=/data/config resolves to wherever
#     the consensus config actually lives on the host — e.g.
#     networks/<network>/cl — instead of the guide's data/config. Same
#     flags/values otherwise.) --------------------------------------------
lighthouse account_manager validator import \
  --datadir="$DATADIR" \
  --directory="$KEYS_DIR" \
  --password-file="$KEYS_DIR/password.txt" \
  --testnet-dir="$TESTNET_DIR" \
  --reuse-password
# --- END: adapted from guide, Step 2-6 -----------------------------------

chown_back
success "Validator key imported into $DATADIR/validators."

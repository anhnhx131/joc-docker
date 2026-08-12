#!/usr/bin/env bash
# staking-deposit-cli/generate-entrypoint.sh — guide Step 2-2.
#
# Runs INSIDE the gulabs/gu-ethstaker-deposit-cli container, as that
# container's entrypoint (overridden by staking-deposit-cli.yml's `deposit-generate`
# service; this file is bind-mounted read-only, the published image itself
# is never rebuilt/modified — see README.md's Security section). Replaces
# the old standalone `./deposit-cli generate` script (removed) — same
# logic, now running inside the container instead of driving `docker run`
# from the host, following eth-docker's compose-file + docker-entrypoint.sh
# convention (see
# https://github.com/ethstaker/eth-docker/blob/main/deposit-cli.yml and
# .../ethstaker-deposit-cli/docker-entrypoint.sh).
#
# Env vars, set by staking-deposit-cli.yml (ultimately from jocv / a human):
#   WITHDRAWAL_ADDRESS   required, 0x + 40 hex chars.
#   HOST_UID / HOST_GID  optional, default 0:0 (root). This container
#                        always runs as root (the stock image's default —
#                        it has no unprivileged user to gosu into, unlike
#                        eth-docker's rebuilt image). chown_back() below
#                        hands the generated files to the calling host
#                        user afterward, same end result as eth-docker's
#                        gosu-then-chown pattern, minus the gosu step.
set -euo pipefail

# --- logging ---------------------------------------------------------------
# Intentionally duplicated from jocv rather than sourced across the
# host/container boundary — see jocv's header comment for the project's
# general stance on keeping files independently readable/portable.
COLOR_RED=$'\033[31m'
COLOR_GREEN=$'\033[32m'
COLOR_YELLOW=$'\033[33m'
COLOR_RESET=$'\033[0m'

info()    { printf '%s\n' "[INFO] $*" >&2; }
success() { printf '%s[OK]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*" >&2; }
warn()    { printf '%s[WARN]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2; }
error()   { printf '%s[ERROR]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2; }
shout()   { printf '%s%s%s\n' "$COLOR_RED" "$*" "$COLOR_RESET" >&2; }
die()     { error "$*"; exit 1; }

is_valid_eth_address() {
  [[ "${1:-}" =~ ^0x[0-9a-fA-F]{40}$ ]]
}

# Unsets MNEMONIC on any exit path (error, Ctrl-C, normal return) so it
# never lingers in memory longer than necessary. Does not touch disk.
install_secret_cleanup_trap() {
  # shellcheck disable=SC2064
  trap 'unset MNEMONIC 2>/dev/null || true' EXIT INT TERM
}

KEYS_DIR=/app/validator_keys
HOST_UID="${HOST_UID:-0}"
HOST_GID="${HOST_GID:-0}"

chown_back() {
  chown -R "$HOST_UID:$HOST_GID" "$KEYS_DIR" 2>/dev/null || true
}

# Prints the deposit data file's path and raw contents to stdout so it's
# easy to copy/paste. This is public data (pubkey, signature, withdrawal
# credentials) — not a secret — but it's still your responsibility to
# submit it through whatever channel the guide/JBF describes (Step 3-1).
print_deposit_summary() {
  local deposit_file="$1"
  {
    echo
    info "Deposit data file (guide Step 3-1 — you submit this yourself, this"
    info "container does not):"
    echo "  $deposit_file"
    echo
    info "Contents, for copy/paste:"
    echo "----------------------------------------------------------------"
  } >&2
  cat "$deposit_file"
  {
    echo
    echo "----------------------------------------------------------------"
  } >&2
}

[[ -n "${WITHDRAWAL_ADDRESS:-}" ]] \
  || die "WITHDRAWAL_ADDRESS env var is required (staking-deposit-cli.yml/jocv should set this)."
is_valid_eth_address "$WITHDRAWAL_ADDRESS" \
  || die "Invalid WITHDRAWAL_ADDRESS '$WITHDRAWAL_ADDRESS'. Expected 0x + 40 hex characters."

mkdir -p "$KEYS_DIR"

shopt -s nullglob
existing_keystores=("$KEYS_DIR"/keystore-*.json)
existing_deposits=("$KEYS_DIR"/deposit_data-*.json)
shopt -u nullglob

if [[ ${#existing_keystores[@]} -gt 0 && ${#existing_deposits[@]} -gt 0 ]]; then
  warn "Validator keys already exist in $KEYS_DIR — skipping generation."
  warn "To regenerate, remove keystore-*.json, deposit_data-*.json and"
  warn "password.txt yourself first (this invalidates any previously"
  warn "submitted deposit data), then re-run."
  print_deposit_summary "${existing_deposits[0]}"
  chown_back
  exit 0
fi

info "Generating password, mnemonic, validator keys and deposit data..."

password_file="$KEYS_DIR/password.txt"
if [[ ! -f "$password_file" ]]; then
  ( umask 077 && openssl rand -base64 24 | tr -d '\n' > "$password_file" )
  chmod 600 "$password_file"
  success "Generated $password_file (chmod 600, >12 characters)."
else
  warn "$password_file already exists, reusing it."
  chmod 600 "$password_file"
fi

# --- Security: no shell history, no lingering shell var, for the mnemonic. ---
set +o history
install_secret_cleanup_trap

info "Running ethstaker-deposit-cli generate-mnemonic (guide Step 2-2, verbatim command)..."
# --- BEGIN: verbatim from guide, Step 2-2 (invoked directly instead of via
#     `docker run ... gulabs/gu-ethstaker-deposit-cli:v0.0.1-gubuild.0`,
#     since this script now runs AS that container's entrypoint — the
#     image's own default entrypoint is `python3 -m ethstaker_deposit`,
#     reproduced literally below. Same image, same subcommand, same
#     flags/values as the guide otherwise.) -------------------------------
echo 'Generating mnemonic with ethstaker-deposit-cli..'

MNEMONIC=$(
  python3 -m ethstaker_deposit --non_interactive --ignore_connectivity generate-mnemonic --mnemonic_language=english
)
if [ -n "$MNEMONIC" ]; then
    echo -e "\033[32m✅ Mnemonic generated successfully.\033[0m"
else
    echo -e "\033[31m❌ Failed to generate mnemonic.\033[0m"
    exit 1
fi
# --- END: verbatim from guide, Step 2-2 ---------------------------------

echo >&2
echo "================================================================" >&2
shout " MNEMONIC — write this down OFFLINE now. It will only be shown once:"
echo >&2
echo " $MNEMONIC" >&2
echo >&2
echo "================================================================" >&2
echo >&2
warn "It is never written to disk, never logged, and never sent over the network."
read -r -p "Have you securely written down this mnemonic OFFLINE? Type 'yes' to continue: " CONFIRM_SAVED
if [[ "$CONFIRM_SAVED" != "yes" ]]; then
  die "Aborted: mnemonic was not confirmed as saved. No keys were generated."
fi

info "Running ethstaker-deposit-cli existing-mnemonic (guide Step 2-2, verbatim command)..."
# --- BEGIN: verbatim from guide, Step 2-2 (invoked directly, same note as
#     the block above) --------------------------------------------------
if [ -n "$MNEMONIC" ]; then
  echo 'Creating validator keys with existing mnemonic..'

  python3 -m ethstaker_deposit --non_interactive --ignore_connectivity existing-mnemonic --num_validators=1 --validator_start_index=0 --mnemonic_language=english --chain=joc --mnemonic="$MNEMONIC" --keystore_password="$(cat "$password_file")" --withdrawal_address="$WITHDRAWAL_ADDRESS" --regular-withdrawal

else
  echo 'Error: Could not generate or extract mnemonic.'
  exit 1
fi
# --- END: verbatim from guide, Step 2-2 ---------------------------------

unset MNEMONIC
clear
set -o history
success "Mnemonic cleared from memory; terminal cleared."

info "Verifying generated files..."
shopt -s nullglob
keystores=("$KEYS_DIR"/keystore-*.json)
deposits=("$KEYS_DIR"/deposit_data-*.json)
shopt -u nullglob
[[ ${#keystores[@]} -ge 1 ]] || die "keystore-*.json not found in $KEYS_DIR"
[[ ${#deposits[@]} -ge 1 ]] || die "deposit_data-*.json not found in $KEYS_DIR"
[[ -f "$password_file" ]] || die "password.txt not found in $KEYS_DIR"
chmod 600 "$KEYS_DIR"/*.json "$password_file"
chown_back
success "Found: $(basename "${keystores[0]}"), $(basename "${deposits[0]}"), password.txt (all chmod 600)."

print_deposit_summary "${deposits[0]}"

shout "=================================================================="
shout "CONFIDENTIAL — do not share with ANYONE, including JBF/admin/BCCloud staff:"
shout "  - the mnemonic (already cleared from this terminal, was never written to disk)"
shout "  - $KEYS_DIR/keystore-*.json"
shout "  - $KEYS_DIR/password.txt"
shout "=================================================================="

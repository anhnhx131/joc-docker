#!/usr/bin/env bash
# scripts/init.sh — set up this Validator Server.
#
# Covers, depending on the chosen ROLE:
#   ROLE=validator (guide Option 2, Recommended) — Step 2-1, 2-2, 2-6, 2-7,
#     2-8: directories, consensus config, password/mnemonic/keys/deposit
#     data, import into Lighthouse, start the Validator Client via
#     docker compose, print the deposit data path + confidentiality warning.
#   ROLE=el-cl — Execution + Consensus clients only, no validator keys at
#     all. NOT covered by the official guide (Option 3: "Organizations
#     selecting Option 3 should contact us directly") — see the big
#     warning below and networks/README.md.
#   ROLE=all — everything above, combined.
#
# Steps 2-3, 2-4, 2-5 (Transaction Cluster, Validator Cluster, Consensus
# HTTP API on BCCloud) are manual UI steps on BCCloud and are NOT performed
# by this script — see README.md.
#
# Safe to re-run: steps that already have output on disk are skipped rather
# than silently overwritten.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

info "=== jocv init — JOC PoSA node setup ==="

# ---------------------------------------------------------------------------
# 0. Preflight
# ---------------------------------------------------------------------------
check_docker
command -v openssl >/dev/null 2>&1 \
  || die "openssl is required (used to generate the keystore password and, for el-cl/all roles, the execution<->consensus JWT secret)."

# ---------------------------------------------------------------------------
# Network + role selection
# ---------------------------------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
  load_env
  info "Existing .env found — reusing NETWORK=${NETWORK:-<unset>}, ROLE=${ROLE:-<unset>}."
  info "(To change network or role, edit .env by hand or start a fresh checkout, then re-run.)"
fi

NETWORK="${NETWORK:-}"
if ! is_supported_network "$NETWORK"; then
  echo "Supported networks: ${SUPPORTED_NETWORKS[*]}" >&2
  read -r -p "Which network? [mainnet]: " NETWORK
  NETWORK="${NETWORK:-mainnet}"
  is_supported_network "$NETWORK" || die "Unsupported network '$NETWORK'. Supported: ${SUPPORTED_NETWORKS[*]}"
fi
export NETWORK

ROLE="${ROLE:-}"
if ! is_supported_role "$ROLE"; then
  cat >&2 <<EOF
Supported roles:
  validator - only the Validator Client, connecting to an external
              Consensus Client (guide Option 2, Recommended)
  el-cl     - only Execution + Consensus clients, no validator duties
  all       - Execution + Consensus + Validator, self-hosted (guide
              Option 3 — NOT documented in the official guide)
EOF
  read -r -p "Which role? [validator]: " ROLE
  ROLE="${ROLE:-validator}"
  is_supported_role "$ROLE" || die "Unsupported role '$ROLE'. Supported: ${SUPPORTED_ROLES[*]}"
fi
export ROLE

EL_CLIENT="${EL_CLIENT:-geth}"
CL_CLIENT="${CL_CLIENT:-lighthouse}"
is_supported_el_client "$EL_CLIENT" \
  || die "Unsupported EL_CLIENT '$EL_CLIENT'. Currently supported: ${SUPPORTED_EL_CLIENTS[*]}."
is_supported_cl_client "$CL_CLIENT" \
  || die "Unsupported CL_CLIENT '$CL_CLIENT'. Currently supported: ${SUPPORTED_CL_CLIENTS[*]}."

PROFILES="$(profiles_for_role "$ROLE")"
COMPOSE_PROFILES="$(echo "$PROFILES" | tr ' ' ',')"
success "Network: $NETWORK | Role: $ROLE (profiles: $COMPOSE_PROFILES) | EL: $EL_CLIENT | CL: $CL_CLIENT"

NEEDS_VALIDATOR=false; NEEDS_EL_CL=false
[[ "$ROLE" == "validator" || "$ROLE" == "all" ]] && NEEDS_VALIDATOR=true
[[ "$ROLE" == "el-cl" || "$ROLE" == "all" ]] && NEEDS_EL_CL=true

EL_DIR="$(network_el_dir "$NETWORK")"
CL_DIR="$(network_cl_dir "$NETWORK")"

# ---------------------------------------------------------------------------
# Step 2-1: directory structure
# ---------------------------------------------------------------------------
info "Preparing data directory structure..."
if [[ "$NEEDS_VALIDATOR" == true ]]; then
  if [[ -d "$KEYS_DIR" ]] && [[ -n "$(ls -A "$KEYS_DIR" 2>/dev/null || true)" ]]; then
    warn "$KEYS_DIR already exists and is not empty."
    if ! confirm "Continue and reuse the existing directory (nothing will be deleted)?"; then
      info "To start over instead: 'jocv reset --data' (permanently deletes"
      info "keys/deposit data/.env — only if you're sure you don't need them)."
      die "Aborted by user. Nothing was changed."
    fi
  fi
  mkdir -p "$KEYS_DIR"
fi
[[ "$NEEDS_EL_CL" == true ]] && mkdir -p "$DATA_DIR/execution" "$DATA_DIR/beacon"
success "Directory structure ready under $DATA_DIR"

cd "$DATA_DIR"

# ---------------------------------------------------------------------------
# Step 2-1 (cont'd): consensus config files (only needed for validator/all —
# el-cl-only nodes still need CL config too, since the beacon node reads it)
# ---------------------------------------------------------------------------
if [[ "$NEEDS_VALIDATOR" == true || "$NEEDS_EL_CL" == true ]]; then
  info "Checking consensus config files under $CL_DIR ..."
  if [[ ! -f "$CL_DIR/config.yaml" || ! -f "$CL_DIR/deposit_contract_block.txt" ]]; then
    cat >&2 <<EOF

Missing consensus config for network '$NETWORK'. This CLI does not
auto-download it: the JOC page is an HTML docs page, not a raw file URL.

Please do this manually:
  1. Open: https://www.japanopenchain.org/vi/docs/developer/connect-joc/mainnet/
     (or get it from JBF/admin for '$NETWORK' if it's not mainnet)
  2. Download "config.yaml" and "deposit_contract_block.txt".
  3. Place both files in: $CL_DIR/
     (or have your team commit them there — see networks/README.md)
  4. Re-run: jocv init

EOF
    die "Consensus config files not found for network '$NETWORK'."
  fi
  success "config.yaml and deposit_contract_block.txt present in $CL_DIR"
  info "config.yaml SHA-256: $(sha256_of "$CL_DIR/config.yaml")"
  info "If this came from a git-committed copy rather than a fresh manual"
  info "download, double check it still matches the official source."
fi

# ---------------------------------------------------------------------------
# Execution + Consensus client setup (ROLE=el-cl or all)
# NOT covered by the official guide — Option 3 is undocumented there.
# ---------------------------------------------------------------------------
if [[ "$NEEDS_EL_CL" == true ]]; then
  shout "=================================================================="
  shout " ROLE includes a self-hosted Execution/Consensus Client (guide"
  shout " Option 3). The official guide does NOT document this — it says"
  shout " 'Organizations selecting Option 3 should contact us directly.'"
  shout " Everything below is this CLI's best-effort convention, not"
  shout " guide-verbatim. Verify all values with JBF/admin. See"
  shout " networks/README.md."
  shout "=================================================================="

  [[ -f "$EL_DIR/genesis.json" ]] \
    || die "Missing $EL_DIR/genesis.json. Get it from JBF/admin and place it there."

  if [[ -z "${EL_CLIENT_IMAGE:-}" ]]; then
    read -r -p "Geth docker image to use for EL_CLIENT_IMAGE (e.g. ethereum/client-go:vX.Y.Z — ask JBF/admin): " EL_CLIENT_IMAGE
    [[ -n "$EL_CLIENT_IMAGE" ]] || die "EL_CLIENT_IMAGE is required for role '$ROLE'."
  fi
  if [[ -z "${EL_NETWORK_ID:-}" ]]; then
    read -r -p "EL_NETWORK_ID for '$NETWORK' (ask JBF/admin): " EL_NETWORK_ID
    [[ -n "$EL_NETWORK_ID" ]] || die "EL_NETWORK_ID is required for role '$ROLE'."
  fi
  export EL_CLIENT_IMAGE EL_NETWORK_ID

  EL_BOOTNODES="$(read_bootnodes_file "$EL_DIR/bootnodes.txt")"
  CL_BOOTNODES="$(read_bootnodes_file "$CL_DIR/bootnodes.txt")"
  [[ -n "$EL_BOOTNODES" ]] || warn "No EL bootnodes at $EL_DIR/bootnodes.txt — execution client may not find peers."
  [[ -n "$CL_BOOTNODES" ]] || warn "No CL bootnodes at $CL_DIR/bootnodes.txt — beacon node may not find peers."

  JWT_FILE="$DATA_DIR/jwt.hex"
  if [[ ! -f "$JWT_FILE" ]]; then
    ( umask 077 && openssl rand -hex 32 > "$JWT_FILE" )
    chmod 600 "$JWT_FILE"
    success "Generated $JWT_FILE (shared secret between execution and beacon)."
  else
    warn "$JWT_FILE already exists, reusing it."
  fi

  if [[ ! -d "$DATA_DIR/execution/geth" ]]; then
    info "Initializing Geth datadir from $EL_DIR/genesis.json (one-time)..."
    docker run --rm \
      -v "$DATA_DIR/execution:/data" \
      -v "$EL_DIR:/network:ro" \
      "$EL_CLIENT_IMAGE" \
      init --datadir=/data /network/genesis.json
    success "Geth datadir initialized."
  else
    info "Geth datadir already initialized, skipping."
  fi
fi

# ---------------------------------------------------------------------------
# Validator setup (ROLE=validator or all) — Guide Step 2-2, 2-6
# ---------------------------------------------------------------------------
if [[ "$NEEDS_VALIDATOR" == true ]]; then
  info "Validator setup: withdrawal address"
  if [[ -n "${VALIDATOR_WITHDRAWAL_ADDRESS:-}" ]] && is_valid_eth_address "${VALIDATOR_WITHDRAWAL_ADDRESS:-}"; then
    info "Using VALIDATOR_WITHDRAWAL_ADDRESS from environment: $VALIDATOR_WITHDRAWAL_ADDRESS"
  else
    while true; do
      read -r -p "Enter the receiver withdrawal address obtained in Step 1-1 (0x...): " VALIDATOR_WITHDRAWAL_ADDRESS
      if is_valid_eth_address "$VALIDATOR_WITHDRAWAL_ADDRESS"; then
        break
      fi
      error "Invalid address. Expected 0x followed by 40 hex characters (42 chars total)."
    done
  fi
  export VALIDATOR_WITHDRAWAL_ADDRESS

  # All three networks (mainnet/testnet/sandbox) share the same
  # ethstaker-deposit-cli chain config, per the guide's Step 2-2 command —
  # --chain is hardcoded to "joc" below regardless of NETWORK.

  shopt -s nullglob
  existing_keystores=("$KEYS_DIR"/keystore-*.json)
  existing_deposits=("$KEYS_DIR"/deposit_data-*.json)
  shopt -u nullglob

  if [[ ${#existing_keystores[@]} -gt 0 && ${#existing_deposits[@]} -gt 0 ]]; then
    warn "Validator keys already exist in $KEYS_DIR — skipping key generation."
    warn "If you really need to regenerate, remove keystore-*.json, deposit_data-*.json" \
         "and password.txt yourself first (this invalidates any previously submitted" \
         "deposit data) and re-run 'jocv init'."
  else
    info "Generating password, mnemonic, validator keys and deposit data..."

    PASSWORD_FILE="$KEYS_DIR/password.txt"
    if [[ ! -f "$PASSWORD_FILE" ]]; then
      ( umask 077 && openssl rand -base64 24 | tr -d '\n' > "$PASSWORD_FILE" )
      chmod 600 "$PASSWORD_FILE"
      success "Generated $PASSWORD_FILE (chmod 600, >12 characters)."
    else
      warn "$PASSWORD_FILE already exists, reusing it."
      chmod 600 "$PASSWORD_FILE"
    fi

    # --- Security: no shell history, no xtrace, for the mnemonic section. ---
    set +o history
    install_secret_cleanup_trap

    info "Running ethstaker-deposit-cli generate-mnemonic (Step 2-2, verbatim command)..."
    # --- BEGIN: verbatim from guide, Step 2-2 -------------------------------
    PWD=$(pwd)
    echo 'Generating mnemonic with ethstaker-deposit-cli..'

    MNEMONIC=$(
      docker run --rm -v "$PWD/validator_keys:/app/validator_keys" gulabs/gu-ethstaker-deposit-cli:v0.0.1-gubuild.0 --non_interactive --ignore_connectivity generate-mnemonic --mnemonic_language=english
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

    info "Running ethstaker-deposit-cli existing-mnemonic (Step 2-2, verbatim command)..."
    # --- BEGIN: verbatim from guide, Step 2-2 -------------------------------
    if [ -n "$MNEMONIC" ]; then
      echo 'Creating validator keys with existing mnemonic..'

      docker run --rm -v "$PWD/validator_keys:/app/validator_keys" gulabs/gu-ethstaker-deposit-cli:v0.0.1-gubuild.0 --non_interactive --ignore_connectivity existing-mnemonic --num_validators=1 --validator_start_index=0 --mnemonic_language=english --chain=joc --mnemonic="$MNEMONIC" --keystore_password="$(cat "$PWD/validator_keys/password.txt")" --withdrawal_address="$VALIDATOR_WITHDRAWAL_ADDRESS" --regular-withdrawal

    else
      echo 'Error: Could not generate or extract mnemonic.'
      exit 1
    fi
    # --- END: verbatim from guide, Step 2-2 ---------------------------------

    unset MNEMONIC
    clear
    set -o history
    success "Mnemonic cleared from shell memory; terminal cleared."

    info "Verifying generated files..."
    shopt -s nullglob
    keystores=("$KEYS_DIR"/keystore-*.json)
    deposits=("$KEYS_DIR"/deposit_data-*.json)
    shopt -u nullglob
    [[ ${#keystores[@]} -ge 1 ]] || die "keystore-*.json not found in $KEYS_DIR"
    [[ ${#deposits[@]} -ge 1 ]] || die "deposit_data-*.json not found in $KEYS_DIR"
    [[ -f "$KEYS_DIR/password.txt" ]] || die "password.txt not found in $KEYS_DIR"
    chmod 600 "$KEYS_DIR"/*.json "$KEYS_DIR/password.txt"
    success "Found: $(basename "${keystores[0]}"), $(basename "${deposits[0]}"), password.txt (all chmod 600)."
  fi

  info "Step 2-6: importing the validator key into the Lighthouse Validator Client..."
  # --- BEGIN: adapted from guide, Step 2-6 (added a second -v mount so
  #     --testnet-dir=/data/config still resolves, now that consensus
  #     config lives under networks/$NETWORK/cl instead of data/config) ---
  docker run --rm \
    -v "$(pwd):/data" \
    -v "$CL_DIR:/data/config:ro" \
    sigp/lighthouse:v7.0.1 \
    lighthouse account_manager validator import \
    --datadir=/data \
    --directory=/data/validator_keys \
    --password-file=/data/validator_keys/password.txt \
    --testnet-dir=/data/config \
    --reuse-password
  # --- END: adapted from guide, Step 2-6 -----------------------------------
  success "Validator key imported."
fi

# ---------------------------------------------------------------------------
# .env
# ---------------------------------------------------------------------------
info "Preparing .env..."
if [[ ! -f "$ENV_FILE" ]]; then
  [[ -f "$ENV_EXAMPLE" ]] || die "$ENV_EXAMPLE not found."
  cp "$ENV_EXAMPLE" "$ENV_FILE"
fi
set_env_var "NETWORK" "$NETWORK"
set_env_var "ROLE" "$ROLE"
set_env_var "COMPOSE_PROFILES" "$COMPOSE_PROFILES"
set_env_var "EL_CLIENT" "$EL_CLIENT"
set_env_var "CL_CLIENT" "$CL_CLIENT"

if [[ "$NEEDS_VALIDATOR" == true ]]; then
  set_env_var "WITHDRAWAL_ADDRESS" "$VALIDATOR_WITHDRAWAL_ADDRESS"
fi

if [[ "$NEEDS_EL_CL" == true ]]; then
  set_env_var "EL_CLIENT_IMAGE" "$EL_CLIENT_IMAGE"
  set_env_var "EL_NETWORK_ID" "$EL_NETWORK_ID"
  set_env_var "EL_BOOTNODES" "$EL_BOOTNODES"
  set_env_var "CL_BOOTNODES" "$CL_BOOTNODES"
fi

if [[ "$ROLE" == "all" ]]; then
  # Self-hosted beacon node is reachable on the compose network by service
  # name. Standard Lighthouse HTTP API port (5052) — verify this is what
  # your beacon service actually exposes if you change its flags.
  set_env_var "BEACON_URL" "http://beacon:5052"
  info "BEACON_URL auto-set to the local beacon service (http://beacon:5052)."
elif [[ "$ROLE" == "validator" ]] && ! grep -q '^BEACON_URL=http://beacon:5052$' "$ENV_FILE"; then
  warn "BEACON_URL is a safe local placeholder until you run:"
  warn "  jocv beacon set http://<bccloud-node-ip>:3500"
  warn "once Step 2-3~2-5 are done on BCCloud."
fi

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
if [[ "$NEEDS_EL_CL" == true ]]; then
  load_env
  check_el_config || die "Fix the above and re-run 'jocv init' (or 'jocv up')."
fi

info "Starting service(s) for role '$ROLE' via docker compose..."
( cd "$JOCV_ROOT" && docker compose up -d )
success "Started. Check status with: jocv status"

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
echo >&2
echo "================================================================" >&2
success "Setup complete for role '$ROLE' on network '$NETWORK'."

if [[ "$NEEDS_VALIDATOR" == true ]]; then
  shopt -s nullglob
  deposit_files=("$KEYS_DIR"/deposit_data-*.json)
  shopt -u nullglob
  DEPOSIT_FILE="${deposit_files[0]:-<not found>}"
  echo >&2
  info "Deposit data file — you will submit this to Launchpad in Step 3-1:"
  echo "  $DEPOSIT_FILE" >&2
  echo >&2
  shout "CONFIDENTIAL — do not share with ANYONE, including JBF/admin/BCCloud staff:"
  shout "  - the mnemonic (already cleared from this terminal, was never written to disk)"
  shout "  - $KEYS_DIR/keystore-*.json"
  shout "  - $KEYS_DIR/password.txt"
fi
if [[ "$NEEDS_EL_CL" == true ]]; then
  echo >&2
  warn "Execution/Consensus client setup is NOT from the official guide (Option 3"
  warn "is undocumented there). Confirm sync status and peer count with 'jocv logs'"
  warn "before trusting this node, and double check genesis/bootnodes/network ID"
  warn "with JBF/admin."
fi
echo "================================================================" >&2

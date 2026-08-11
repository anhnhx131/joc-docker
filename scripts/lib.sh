#!/usr/bin/env bash
# scripts/lib.sh — shared helpers, sourced by every jocv subcommand script.
#
# This file is intentionally boring: logging, confirmation prompts, path
# constants, and basic validators. No JOC-specific business logic lives
# here — that stays in the step scripts so it stays easy to diff against
# the original guide.
set -euo pipefail

# --- paths ----------------------------------------------------------------
# JOCV_ROOT = repo root (parent of scripts/), regardless of caller's cwd.
JOCV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$JOCV_ROOT/data"
KEYS_DIR="$DATA_DIR/validator_keys"
NETWORKS_DIR="$JOCV_ROOT/networks"
ENV_FILE="$JOCV_ROOT/.env"
ENV_EXAMPLE="$JOCV_ROOT/.env.example"

# --- supported networks / clients / roles ----------------------------------
# Keep these allow-lists as the single source of truth for what jocv
# currently supports. Adding a new entry here is a deliberate, reviewed
# decision — not something any script should infer on its own.
SUPPORTED_NETWORKS=(mainnet testnet sandbox)
SUPPORTED_EL_CLIENTS=(geth)          # planned, not yet supported: nethermind, besu
SUPPORTED_CL_CLIENTS=(lighthouse)    # planned, not yet supported: prysm
SUPPORTED_ROLES=(validator el-cl all)

# --- logging ----------------------------------------------------------------
COLOR_RED=$'\033[31m'
COLOR_GREEN=$'\033[32m'
COLOR_YELLOW=$'\033[33m'
COLOR_BOLD=$'\033[1m'
COLOR_RESET=$'\033[0m'

info()    { printf '%s\n' "[INFO] $*" >&2; }
success() { printf '%s[OK]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*" >&2; }
warn()    { printf '%s[WARN]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2; }
error()   { printf '%s[ERROR]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2; }
shout()   { printf '%s%s%s\n' "$COLOR_BOLD$COLOR_RED" "$*" "$COLOR_RESET" >&2; }
die()     { error "$*"; exit 1; }

# confirm "question" -> returns 0 (success) only if the user explicitly
# answers y/yes. Anything else (including empty input) is treated as "no".
confirm() {
  local prompt="${1:-Are you sure?}"
  local answer=""
  read -r -p "$prompt [y/N] " answer || true
  case "$answer" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# confirm_strict "question" "phrase" -> returns 0 only if the user types
# the exact phrase back (case-sensitive). For actions with no undo (e.g.
# deleting key material) where a fat-fingered 'y' shouldn't be enough.
confirm_strict() {
  local prompt="$1" phrase="$2"
  local answer=""
  read -r -p "$prompt (type '$phrase' to confirm): " answer || true
  [[ "$answer" == "$phrase" ]]
}

# --- preflight checks --------------------------------------------------------
check_docker() {
  command -v docker >/dev/null 2>&1 \
    || die "Docker is not installed. See https://docs.docker.com/engine/install/"
  docker info >/dev/null 2>&1 \
    || die "Docker daemon is not running (or not accessible). Start Docker and re-run."
  docker compose version >/dev/null 2>&1 \
    || die "'docker compose' (v2 plugin) is not available. Install/upgrade Docker."
  success "Docker is installed and running."
}

# --- validators ---------------------------------------------------------------
# Ethereum-style address: 0x + 40 hex chars = 42 chars total.
is_valid_eth_address() {
  local addr="${1:-}"
  [[ "$addr" =~ ^0x[0-9a-fA-F]{40}$ ]]
}

is_valid_url() {
  local url="${1:-}"
  [[ "$url" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?(/.*)?$ ]]
}

# Cross-platform SHA-256 (macOS has `shasum`, most Linux has `sha256sum`).
# Used so an operator can eyeball/compare a config file's checksum against
# the official source before applying it — config.yaml controls consensus
# rules, so a wrong file is a real risk, not just a formatting nit.
sha256_of() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  else
    echo "unavailable (no sha256sum/shasum found)"
  fi
}

# --- network / client / role selection ---------------------------------------
_list_contains() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

is_supported_network()   { _list_contains "${1:-}" "${SUPPORTED_NETWORKS[@]}"; }
is_supported_el_client() { _list_contains "${1:-}" "${SUPPORTED_EL_CLIENTS[@]}"; }
is_supported_cl_client() { _list_contains "${1:-}" "${SUPPORTED_CL_CLIENTS[@]}"; }
is_supported_role()      { _list_contains "${1:-}" "${SUPPORTED_ROLES[@]}"; }

# docker compose profile name(s) to activate for a given ROLE, space-separated.
#   validator -> only the Validator Client (guide Option 2: connects to an
#                external Consensus Client, e.g. BCCloud)
#   el-cl     -> only Execution + Consensus clients, no validator duties
#   all       -> everything, self-hosted (guide Option 3)
profiles_for_role() {
  case "${1:-}" in
    validator) echo "validator" ;;
    el-cl)     echo "el-cl" ;;
    all)       echo "el-cl validator" ;;
    *)         return 1 ;;
  esac
}

# Enforces that EL_CLIENT_IMAGE / EL_NETWORK_ID are set before starting a
# role that includes the execution/beacon services. Deliberately checked
# here in bash, not via docker-compose's ':?' required-variable syntax —
# compose interpolates every service's variables at parse time regardless
# of active profile, so a compose-level requirement here would also break
# ROLE=validator, which never touches these services at all.
check_el_config() {
  local missing=()
  [[ -n "${EL_CLIENT_IMAGE:-}" ]] || missing+=("EL_CLIENT_IMAGE")
  [[ -n "${EL_NETWORK_ID:-}" ]]   || missing+=("EL_NETWORK_ID")
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required .env value(s) for ROLE=${ROLE:-<unset>}: ${missing[*]}"
    cat >&2 <<EOF

There is no default for these — this repo does not know which Geth
version/network ID JOC requires (the official guide does not document
Option 3). Get the correct values from JBF/admin, set them in .env, then
retry. See networks/README.md.
EOF
    return 1
  fi
}

network_dir()        { echo "$NETWORKS_DIR/$1"; }
network_el_dir()     { echo "$NETWORKS_DIR/$1/el"; }
network_cl_dir()     { echo "$NETWORKS_DIR/$1/cl"; }
network_phases_dir() { echo "$NETWORKS_DIR/$1/cl/phases"; }

# set_env_var KEY VALUE — create or update a KEY=VALUE line in $ENV_FILE.
set_env_var() {
  local key="$1" value="$2"
  [[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found."
  local tmp
  tmp="$(mktemp)"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" > "$tmp"
  else
    cp "$ENV_FILE" "$tmp"
    echo "${key}=${value}" >> "$tmp"
  fi
  mv "$tmp" "$ENV_FILE"
}

# Plain-text bootnode list -> single comma-joined string for a --bootnodes /
# --boot-nodes flag. One entry per line; blank lines and '#' comments
# ignored. Not real YAML parsing on purpose — see networks/README.md.
read_bootnodes_file() {
  local f="$1"
  [[ -f "$f" ]] || { echo ""; return 0; }
  grep -vE '^[[:space:]]*(#|$)' "$f" | paste -sd, -
}

# Loads .env into the current shell's environment (auto-export), so
# scripts can read NETWORK/ROLE/EL_CLIENT/CL_CLIENT/etc. Assumes .env is
# trusted content that jocv itself wrote — same trust model docker
# compose already applies to .env.
load_env() {
  [[ -f "$ENV_FILE" ]] || return 1
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

# --- secret hygiene -----------------------------------------------------------
# Installs a trap so that if the script handling the mnemonic exits early
# (error, Ctrl-C, etc.) the MNEMONIC variable does not linger in the shell's
# memory/environment any longer than necessary. This does NOT write anything
# to disk or logs — it only unsets the in-memory shell variable.
install_secret_cleanup_trap() {
  # shellcheck disable=SC2064
  trap 'unset MNEMONIC 2>/dev/null || true' EXIT INT TERM
}

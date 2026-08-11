#!/usr/bin/env bash
# scripts/down.sh — stop all service(s) started for the current ROLE.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

check_docker
[[ -f "$ENV_FILE" ]] && load_env || true

if [[ "${ROLE:-validator}" == "validator" || "${ROLE:-validator}" == "all" ]]; then
  warn "Guide note (Step 3-2): do not stop the Validator Client while awaiting activation."
fi
confirm "Stop the node now?" || die "Aborted."

( cd "$JOCV_ROOT" && docker compose down )
success "Stopped. Start again with: jocv up"

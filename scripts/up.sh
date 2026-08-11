#!/usr/bin/env bash
# scripts/up.sh — (re)start whichever service(s) the current ROLE needs,
# with the current .env / docker-compose.yml (e.g. after 'jocv update'
# pulled a new docker-compose.yml, or after editing .env by hand).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

check_docker
[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found. Run 'jocv init' first."
load_env

if [[ "${ROLE:-}" == "el-cl" || "${ROLE:-}" == "all" ]]; then
  check_el_config || die "Fix .env, then retry."
fi

( cd "$JOCV_ROOT" && docker compose up -d )
success "Up (role: ${ROLE:-<unset>}, profiles: ${COMPOSE_PROFILES:-<unset>}). Check with: jocv status"

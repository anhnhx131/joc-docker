#!/usr/bin/env bash
# scripts/logs.sh — follow a service's logs. For a one-shot health check
# across all active services instead, use 'jocv status'.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

check_docker
[[ -f "$ENV_FILE" ]] && load_env || true
ROLE="${ROLE:-validator}"

ACTIVE=()
[[ "$ROLE" == "validator" || "$ROLE" == "all" ]] && ACTIVE+=("validator")
[[ "$ROLE" == "el-cl" || "$ROLE" == "all" ]] && ACTIVE+=("execution" "beacon")

SERVICE="${1:-}"
if [[ -z "$SERVICE" ]]; then
  if [[ ${#ACTIVE[@]} -eq 1 ]]; then
    SERVICE="${ACTIVE[0]}"
  else
    error "Multiple services are active for ROLE=$ROLE: ${ACTIVE[*]}"
    echo "Usage: jocv logs <service>   (one of: ${ACTIVE[*]})" >&2
    exit 1
  fi
fi

( cd "$JOCV_ROOT" && docker compose logs -f --tail 100 "$SERVICE" )

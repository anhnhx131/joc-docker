#!/usr/bin/env bash
# scripts/status.sh — check node health for whichever service(s) the
# current ROLE runs. Per Guide Step 3-2 for the validator container; the
# execution/beacon checks are this project's own addition (not from the
# guide, which doesn't cover self-hosting them).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

check_docker
[[ -f "$ENV_FILE" ]] && load_env || true
ROLE="${ROLE:-validator}"

SERVICES=()
[[ "$ROLE" == "validator" || "$ROLE" == "all" ]] && SERVICES+=("validator")
[[ "$ROLE" == "el-cl" || "$ROLE" == "all" ]] && SERVICES+=("execution" "beacon")

overall_ok=true
for svc in "${SERVICES[@]}"; do
  echo >&2
  if ! docker ps --filter "name=^/${svc}\$" --format '{{.Names}}' | grep -q "^${svc}\$"; then
    error "Container '$svc' is not running."
    docker ps -a --filter "name=^/${svc}\$"
    overall_ok=false
    continue
  fi
  success "Container '$svc' is running:"
  docker ps --filter "name=^/${svc}\$"

  info "Last 20 log lines for '$svc':"
  docker logs --tail 20 "$svc" 2>&1 || true

  if [[ "$svc" == "validator" ]]; then
    not_attesting_count="$(docker logs --tail 500 "$svc" 2>&1 | grep -c "Not attesting" || true)"
    if [[ "$not_attesting_count" -gt 0 ]]; then
      warn "Found $not_attesting_count recent 'Not attesting' log line(s)."
      warn "Per the guide (Step 3-2): if this keeps appearing for more than"
      warn "15-20 minutes (after the first 5-10 minutes of startup), the"
      warn "validator is not operating properly. Contact JBF/admin if it persists."
    else
      success "No 'Not attesting' messages in the last 500 log lines."
    fi
  fi
done

[[ "$overall_ok" == true ]] || exit 1

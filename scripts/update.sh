#!/usr/bin/env bash
# scripts/update.sh — update this CLI itself (scripts, docker-compose.yml,
# and any config-templates/ files your team has committed) via `git pull`.
#
# Loosely modeled on eth-docker's `ethd update`, but deliberately much
# simpler:
#   - no OS package management
#   - no .env schema migration (there are only two variables here)
#   - no automatic container restart and no automatic config apply
#
# It only fetches code. Applying a new consensus config is still a
# separate, explicitly-confirmed step (`jocv update-config <phase>`), and
# restarting the validator container is still your call (`jocv up`).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

[[ -d "$JOCV_ROOT/.git" ]] \
  || die "$JOCV_ROOT is not a git checkout. Clone this repo with 'git clone' to use 'jocv update'."
command -v git >/dev/null 2>&1 || die "git is required for 'jocv update'."

cd "$JOCV_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  warn "This checkout has local changes (git status is not clean):"
  git status --short >&2
  die "Commit, stash, or discard local changes before running 'jocv update'."
fi

BRANCH="$(git branch --show-current)"
[[ -n "$BRANCH" ]] || die "Not on a branch (detached HEAD). Check out a branch before updating."

info "Fetching latest changes for '$BRANCH' from origin..."
git fetch origin "$BRANCH"

behind_count="$(git rev-list --count "HEAD..origin/$BRANCH")"
if [[ "$behind_count" -eq 0 ]]; then
  success "Already up to date ($(git rev-parse --short HEAD))."
  exit 0
fi

info "$behind_count new commit(s) available on '$BRANCH':"
git log --oneline "HEAD..origin/$BRANCH" >&2
echo >&2

confirm "Pull these changes now?" || die "Aborted. Nothing was changed."

# Look ahead at what's changing under paths that affect a running
# validator, so we can tell you what to do next instead of acting on it.
compose_changed=false
if git diff --name-only "HEAD..origin/$BRANCH" | grep -qx 'docker-compose.yml'; then
  compose_changed=true
fi
phases_changed="$(git diff --name-only "HEAD..origin/$BRANCH" -- 'networks/*/cl/phases/' || true)"
el_cl_changed="$(git diff --name-only "HEAD..origin/$BRANCH" -- 'networks/*/el/' || true)"

git pull --ff-only origin "$BRANCH"
success "Updated to $(git rev-parse --short HEAD)."

if [[ "$compose_changed" == true ]]; then
  warn "docker-compose.yml changed. Review the diff, then run 'jocv up' to apply."
fi
if [[ -n "$phases_changed" ]]; then
  warn "New/changed phase config(s) pulled in:"
  echo "$phases_changed" | sed 's/^/  /' >&2
  warn "Run 'jocv update-config <phase>' for the relevant phase once JBF/admin"
  warn "officially announces it — do not apply on your own initiative."
fi
if [[ -n "$el_cl_changed" ]]; then
  warn "Execution-layer network file(s) changed (genesis/bootnodes):"
  echo "$el_cl_changed" | sed 's/^/  /' >&2
  warn "These normally only change for a new network launch, not a routine"
  warn "hard fork phase. Confirm with JBF/admin before re-running 'jocv init'"
  warn "or restarting the execution service."
fi

#!/usr/bin/env bash
# scripts/install.sh — install Docker (Engine + compose plugin), the only
# prerequisite jocv actually needs.
#
# Deliberately narrow compared to eth-docker's `ethd install`: this only
# installs Docker. It does NOT tune the OS (swappiness, noatime, chrony/NTP),
# does NOT install unrelated packages, and does NOT touch anything under
# validator_keys/. A tool that's about to handle a mnemonic shouldn't also
# be doing broad root-level OS provisioning — see README.md's
# "Compared to eth-docker's ethd" section.
#
# Every `sudo` command this script will run is shown to you before it
# runs, and you're asked to confirm once before any of them execute.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

info "=== jocv install — Docker prerequisite check/install ==="

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  success "Docker is already installed and running, with the compose plugin. Nothing to do."
  docker --version
  docker compose version
  exit 0
fi

[[ -f /etc/os-release ]] || die "Cannot detect your OS (/etc/os-release not found). Install Docker manually: https://docs.docker.com/engine/install/"
# shellcheck disable=SC1091
source /etc/os-release
OS_ID="${ID:-}"
OS_ID_LIKE="${ID_LIKE:-}"

command -v sudo >/dev/null 2>&1 || die "sudo is required to install Docker. Install Docker manually if you don't have it: https://docs.docker.com/engine/install/"

run_steps() {
  # Prints every command first, asks once, then runs them for real.
  local -a cmds=("$@")
  echo >&2
  info "The following commands will run (all via sudo where needed):"
  local c
  for c in "${cmds[@]}"; do echo "  $ $c" >&2; done
  echo >&2
  confirm "Proceed?" || die "Aborted. Nothing was installed."
  for c in "${cmds[@]}"; do
    info "Running: $c"
    eval "$c"
  done
}

case "$OS_ID" in
  ubuntu | debian)
    info "Detected $PRETTY_NAME — using Docker's official apt repository."
    run_steps \
      "sudo apt-get update -y" \
      "sudo apt-get install -y ca-certificates curl gnupg" \
      "sudo install -m 0755 -d /etc/apt/keyrings" \
      "sudo curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg -o /etc/apt/keyrings/docker.asc" \
      "sudo chmod a+r /etc/apt/keyrings/docker.asc" \
      "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${OS_ID} \$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null" \
      "sudo apt-get update -y" \
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    ;;
  amzn | rhel | centos | fedora | rocky | almalinux)
    warn "Detected $PRETTY_NAME. Docker's official repos target upstream"
    warn "RHEL/CentOS/Fedora — this path is best-effort on Amazon Linux and"
    warn "similar distros, not as thoroughly verified as the Ubuntu/Debian path."
    run_steps \
      "sudo dnf -y install dnf-plugins-core" \
      "sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo" \
      "sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" \
      "sudo systemctl enable --now docker"
    ;;
  *)
    if [[ "$OS_ID_LIKE" == *debian* ]]; then
      die "Unrecognized distro '$OS_ID' (debian-like). Follow the Debian steps manually: https://docs.docker.com/engine/install/debian/"
    fi
    die "Unsupported/unrecognized distro '$OS_ID' ($PRETTY_NAME). Install Docker manually: https://docs.docker.com/engine/install/"
    ;;
esac

# Make sure the daemon is actually up (apt path installs+starts it via the
# systemd unit shipped in the package; this is a no-op if already running).
sudo systemctl enable --now docker >/dev/null 2>&1 || true

if ! groups "$USER" | grep -qw docker; then
  info "Adding $USER to the 'docker' group (to run docker without sudo)..."
  sudo usermod -aG docker "$USER"
  warn "Group membership only takes effect in a NEW login session."
  warn "Log out and back in (or run: newgrp docker) before using 'jocv'."
else
  info "$USER is already in the 'docker' group."
fi

echo >&2
if docker info >/dev/null 2>&1; then
  success "Docker installed and working:"
else
  warn "Docker was installed, but this shell can't talk to it yet — most"
  warn "likely you need to log out/in (or run 'newgrp docker') to pick up"
  warn "the new 'docker' group membership."
fi
docker --version || true
docker compose version || true

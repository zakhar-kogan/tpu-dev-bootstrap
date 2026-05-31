#!/usr/bin/env bash
set -Eeuo pipefail

# Thin bootstrap — clones/updates the repo and hands off to install.sh.
# Usage: curl -fsSL https://raw.githubusercontent.com/zakhar-kogan/tpu-dev-bootstrap/main/bootstrap.sh | bash -s -- [options]

REPO_URL="https://github.com/zakhar-kogan/tpu-dev-bootstrap.git"
INSTALL_DIR="${HOME}/.local/share/tpu-dev/bootstrap"

if ! command -v git &>/dev/null; then
  echo "Installing git..."
  sudo apt-get update -qq && sudo apt-get install -y -qq git
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "Updating tpu-dev-bootstrap..."
  git -C "$INSTALL_DIR" pull --ff-only -q
else
  echo "Cloning tpu-dev-bootstrap..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

exec "$INSTALL_DIR/install.sh" "$@"

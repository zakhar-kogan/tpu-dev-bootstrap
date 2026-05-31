#!/usr/bin/env bash
# lib/env.sh — System dependencies, uv install, and venv creation.

METADATA_BASE="http://metadata.google.internal/computeMetadata/v1"

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "This installer targets Linux TPU VMs."
}

metadata_get() {
  local path="$1"
  curl -fsS --connect-timeout 1 --max-time 2 \
    -H "Metadata-Flavor: Google" \
    "$METADATA_BASE/$path" 2>/dev/null || true
}

detect_gcp_metadata() {
  log "Detecting GCP/TPU metadata"
  local zone_path
  [[ -n "$GCP_PROJECT" ]] || GCP_PROJECT="$(metadata_get project/project-id)"
  if [[ -z "$GCP_ZONE" ]]; then
    zone_path="$(metadata_get instance/zone)"
    GCP_ZONE="${zone_path##*/}"
  fi
  [[ -n "$TPU_NAME" ]] || TPU_NAME="$(metadata_get instance/name)"
  [[ -n "$TPU_EXTERNAL_IP" ]] || TPU_EXTERNAL_IP="$(metadata_get instance/network-interfaces/0/access-configs/0/external-ip)"
}

install_system_deps() {
  log "Installing system dependencies"
  if command -v apt-get >/dev/null 2>&1; then
    run sudo apt-get update
    local base_pkgs=(ca-certificates curl git build-essential jq openssl)
    if ((${#APT_PACKAGES[@]} > 0)); then
      log "Extra apt packages: ${APT_PACKAGES[*]}"
      run sudo apt-get install -y "${base_pkgs[@]}" "${APT_PACKAGES[@]}"
    else
      run sudo apt-get install -y "${base_pkgs[@]}"
    fi
  else
    warn "apt-get not found; install curl/git/build tools manually if missing."
    if ((${#APT_PACKAGES[@]} > 0)); then
      warn "Skipping extra apt packages (no apt-get): ${APT_PACKAGES[*]}"
    fi
  fi
}

install_uv() {
  if command -v uv >/dev/null 2>&1; then
    log "uv already installed: $(command -v uv)"
    return
  fi
  log "Installing uv"
  if [[ "$DRY_RUN" == "yes" ]]; then
    echo "DRY-RUN: curl -LsSf https://astral.sh/uv/install.sh | sh"
  else
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  command -v uv >/dev/null 2>&1 || die "uv install did not put uv on PATH"
}

create_env() {
  log "Preparing Python environment at $ENV_DIR"
  if [[ -d "$VENV_DIR" && "$RECREATE" == "yes" ]]; then
    run rm -rf "$VENV_DIR"
  fi
  run mkdir -p "$ENV_DIR"
  if [[ ! -d "$VENV_DIR" ]]; then
    run uv venv --python "$PYTHON_VERSION" --seed "$VENV_DIR"
  else
    local actual_ver
    actual_ver="$("$VENV_DIR/bin/python" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
    if [[ -n "$actual_ver" && "$actual_ver" != "$PYTHON_VERSION"* ]]; then
      warn "Existing venv uses Python $actual_ver but you requested $PYTHON_VERSION."
      warn "Re-run with --recreate to rebuild the venv with the new Python version."
      warn "Continuing with Python $actual_ver."
    else
      log "Reusing existing venv (Python $actual_ver)"
    fi
  fi
}

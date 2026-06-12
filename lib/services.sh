#!/usr/bin/env bash
# lib/services.sh — Systemd service templating, secrets, and helper script installation.

# Render a systemd template by replacing {{KEY}} placeholders with values.
# Usage: render_template <template_file> KEY1 VAL1 KEY2 VAL2 ...
render_template() {
  local template="$1"; shift
  local content
  content="$(cat "$template")"
  while (( $# >= 2 )); do
    content="${content//\{\{$1\}\}/$2}"
    shift 2
  done
  printf '%s\n' "$content"
}

# Write a rendered service unit to disk.
write_service() {
  local file="$1" content="$2"
  run mkdir -p "$SYSTEMD_USER_DIR"
  if [[ "$DRY_RUN" == "yes" ]]; then
    echo "DRY-RUN: write $file"
  else
    printf '%s\n' "$content" > "$file"
  fi
}

# Enable and (re)start a user service.
enable_service() {
  local service_name="$1"
  if [[ "$DRY_RUN" != "yes" ]]; then
    systemctl --user daemon-reload
    systemctl --user enable "$service_name"
    systemctl --user restart "$service_name"
  fi
}

generate_secret() {
  run mkdir -p "$CONFIG_HOME" "$LOG_DIR"
  local saved_jupyter_port="$JUPYTER_PORT"
  local saved_marimo_port="$MARIMO_PORT"
  local saved_env_dir="$ENV_DIR"

  if [[ -f "$SECRETS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SECRETS_FILE"
  fi

  JUPYTER_PORT="$saved_jupyter_port"
  MARIMO_PORT="$saved_marimo_port"
  ENV_DIR="$saved_env_dir"

  if [[ -z "${JUPYTER_TOKEN:-}" ]]; then
    JUPYTER_TOKEN="$("$VENV_DIR/bin/python" - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)"
  fi
  if [[ "$ENABLE_MARIMO" == "yes" && -z "${MARIMO_TOKEN:-}" ]]; then
    MARIMO_TOKEN="$("$VENV_DIR/bin/python" - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)"
  fi
  if [[ "$DRY_RUN" != "yes" ]]; then
    umask 077
    {
      printf 'JUPYTER_TOKEN=%q\n' "$JUPYTER_TOKEN"
      [[ -n "$MARIMO_TOKEN" ]] && printf 'MARIMO_TOKEN=%q\n' "$MARIMO_TOKEN"
      printf 'JUPYTER_PORT=%q\n' "$JUPYTER_PORT"
      printf 'MARIMO_PORT=%q\n' "$MARIMO_PORT"
      printf 'ENV_DIR=%q\n' "$ENV_DIR"
    } > "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE"
  fi
}

install_jupyter_service() {
  [[ "$ENABLE_JUPYTER" == "yes" ]] || return 0
  local bind_ip="127.0.0.1" allow_remote="False"
  if [[ "$PUBLIC_JUPYTER" == "yes" ]]; then
    bind_ip="0.0.0.0"
    allow_remote="True"
  fi
  log "Installing JupyterLab user service"
  local libdir
  libdir="$("$VENV_DIR/bin/python" -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))" 2>/dev/null || true)"
  local content
  content="$(render_template "$SCRIPT_DIR/systemd/jupyter.service.template" \
    ENV_DIR "$ENV_DIR" \
    VENV_DIR "$VENV_DIR" \
    HOME "$HOME" \
    BIND_IP "$bind_ip" \
    JUPYTER_PORT "$JUPYTER_PORT" \
    JUPYTER_TOKEN "$JUPYTER_TOKEN" \
    ALLOW_REMOTE_ACCESS "$allow_remote" \
    LD_LIBRARY_PATH "$libdir"
  )"
  write_service "$SYSTEMD_USER_DIR/tpu-jupyter.service" "$content"
  enable_service "tpu-jupyter.service"
  if [[ "$DRY_RUN" != "yes" ]]; then
    loginctl enable-linger "$USER" >/dev/null 2>&1 || true
  fi
}

install_marimo_service() {
  [[ "$ENABLE_MARIMO" == "yes" ]] || return 0
  local bind_ip="127.0.0.1"
  if [[ "$PUBLIC_MARIMO" == "yes" ]]; then
    bind_ip="0.0.0.0"
  fi
  log "Installing Marimo user service"
  local libdir
  libdir="$("$VENV_DIR/bin/python" -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))" 2>/dev/null || true)"
  local content
  content="$(render_template "$SCRIPT_DIR/systemd/marimo.service.template" \
    ENV_DIR "$ENV_DIR" \
    VENV_DIR "$VENV_DIR" \
    HOME "$HOME" \
    BIND_IP "$bind_ip" \
    MARIMO_PORT "$MARIMO_PORT" \
    MARIMO_TOKEN "$MARIMO_TOKEN" \
    LD_LIBRARY_PATH "$libdir"
  )"
  write_service "$SYSTEMD_USER_DIR/tpu-marimo.service" "$content"
  enable_service "tpu-marimo.service"
}

# Copy standalone helper scripts and set up the login banner.
install_helper_scripts() {
  log "Installing helper scripts"
  run mkdir -p "$HOME/.local/bin"

  if [[ "$DRY_RUN" != "yes" ]]; then
    install -m 755 "$SCRIPT_DIR/scripts/tpu-workspace" "$HOME/.local/bin/tpu-workspace"
    install -m 755 "$SCRIPT_DIR/scripts/tpu-status"    "$HOME/.local/bin/tpu-status"

    # Install banner script and add a one-line source to .bashrc.
    local banner_dest="$HOME/.local/share/tpu-dev/banner.sh"
    mkdir -p "$(dirname "$banner_dest")"
    install -m 644 "$SCRIPT_DIR/scripts/tpu-banner.sh" "$banner_dest"

    local source_line="[[ -f $banner_dest ]] && source $banner_dest"
    if ! grep -qF "$source_line" "$HOME/.bashrc" 2>/dev/null; then
      printf '\n# TPU development environment welcome banner\n%s\n' "$source_line" >> "$HOME/.bashrc"
    fi
  fi
}

register_kernel() {
  log "Registering Jupyter kernel"
  run "$VENV_DIR/bin/python" -m ipykernel install --user --name "$ENV_NAME" --display-name "TPU Dev ($ENV_NAME)"
}

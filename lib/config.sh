#!/usr/bin/env bash
# lib/config.sh — Configuration loading (.env format) and secrets management.

download_config() {
  local src="$1" dst
  if [[ "$src" =~ ^https?:// ]]; then
    dst="$(mktemp)"
    curl -fsSL "$src" -o "$dst"
    printf '%s' "$dst"
  else
    [[ -f "$src" ]] || die "Config not found: $src"
    printf '%s' "$src"
  fi
}

apply_config() {
  local config_file="$1"
  # Source the .env file. Only known variables are picked up because the
  # installer initialises all globals before this runs.
  set -a
  # shellcheck disable=SC1090
  source "$config_file"
  set +a
}

# Load previously saved ports/env from secrets.env to use as defaults.
load_saved_config() {
  local secrets_file="$1"
  if [[ -f "$secrets_file" ]]; then
    local _saved
    _saved="$(grep -E '^JUPYTER_PORT=' "$secrets_file" | cut -d= -f2- | tr -d \'\")"
    [[ -n "$_saved" ]] && JUPYTER_PORT="$_saved"
    _saved="$(grep -E '^MARIMO_PORT=' "$secrets_file" | cut -d= -f2- | tr -d \'\")"
    [[ -n "$_saved" ]] && MARIMO_PORT="$_saved"
  fi
}

#!/usr/bin/env bash
set -Eeuo pipefail

echo "Jupyter service:"
systemctl --user --no-pager status tpu-jupyter.service || true

echo
echo "Marimo service:"
systemctl --user --no-pager status tpu-marimo.service || true

echo
echo "Secrets/config:"
if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/tpu-dev/secrets.env" ]]; then
  sed -E 's/(JUPYTER_TOKEN=).+/\1<redacted>/' "${XDG_CONFIG_HOME:-$HOME/.config}/tpu-dev/secrets.env"
else
  echo "No secrets file found."
fi

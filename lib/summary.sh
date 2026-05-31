#!/usr/bin/env bash
# lib/summary.sh — Final status output and Cloudflare tunnel print.

SEP="────────────────────────────────────────────────────────"

print_cloudflare() {
  [[ "$CLOUDFLARE_TUNNEL" == "yes" ]] || return 0
  printf '\nCloudflare quick tunnel:\n'
  printf '  cloudflared tunnel --url http://127.0.0.1:%s\n' "$JUPYTER_PORT"
  if command -v cloudflared >/dev/null 2>&1 && have_tty; then
    if [[ "$(prompt_yes_no "Start Cloudflare quick tunnel now" "no")" == "yes" ]]; then
      run cloudflared tunnel --url "http://127.0.0.1:$JUPYTER_PORT"
    fi
  else
    warn "cloudflared not found. Install it to use quick tunnels."
  fi
}

print_summary() {
  local jlab_host="127.0.0.1"
  local marimo_host="127.0.0.1"
  [[ "$PUBLIC_JUPYTER" == "yes" ]] && jlab_host="${TPU_EXTERNAL_IP:-<TPU_EXTERNAL_IP>}"
  [[ "$PUBLIC_MARIMO"  == "yes" ]] && marimo_host="${TPU_EXTERNAL_IP:-<TPU_EXTERNAL_IP>}"

  local ssh_target="${TPU_NAME:-<TPU_NAME>}"
  local ssh_zone="${GCP_ZONE:-<ZONE>}"
  local project_flag="${GCP_PROJECT:+--project=$GCP_PROJECT}"

  printf '\n%s\n' "$SEP"
  printf '✅  Done  ·  env: %s\n' "$ENV_DIR"
  printf '         ·  secrets: %s\n' "$SECRETS_FILE"

  # ── SSH ──
  printf '\n%s\n' "$SEP"
  printf '🔑  SSH\n\n'
  printf '  gcloud:  gcloud compute tpus tpu-vm ssh %s %s --zone=%s\n' \
    "$ssh_target" "$project_flag" "$ssh_zone"
  local ssh_host="${TPU_EXTERNAL_IP:-<TPU_EXTERNAL_IP>}"
  if [[ -f "$SHARE_SSH_KEY_PATH" ]]; then
    printf '  direct:  ssh -i %s -o IdentitiesOnly=yes -p %s %s@%s\n' \
      "$SHARE_SSH_KEY_PATH" "$SSH_PORT" "$SHARE_SSH_USER" "$ssh_host"
    printf '  key:     cat %s\n' "$SHARE_SSH_KEY_PATH"
    local command_file="$SHARE_SSH_KEY_PATH.add-to-tpu.sh"
    [[ -f "$command_file" ]] && printf '  workers: %s\n' "$command_file"
  fi

  # ── JupyterLab ──
  if [[ "$ENABLE_JUPYTER" == "yes" ]]; then
    printf '\n%s\n' "$SEP"
    printf '🧪  JupyterLab\n\n'
    printf '  url:     http://%s:%s/lab?token=%s\n' "$jlab_host" "$JUPYTER_PORT" "$JUPYTER_TOKEN"
    if [[ "$PUBLIC_JUPYTER" == "yes" ]]; then
      printf '  tunnel:  gcloud compute tpus tpu-vm ssh %s %s --zone=%s -- -L %s:127.0.0.1:%s\n' \
        "$ssh_target" "$project_flag" "$ssh_zone" "$JUPYTER_PORT" "$JUPYTER_PORT"
      printf '           http://127.0.0.1:%s/lab?token=%s\n' "$JUPYTER_PORT" "$JUPYTER_TOKEN"
    fi
    printf '  status:  systemctl --user status tpu-jupyter.service\n'
    printf '  logs:    journalctl --user -u tpu-jupyter.service -f\n'
    printf '  kernel:  TPU Dev (%s)  ← select in VS Code / JupyterLab\n' "$ENV_NAME"
  fi

  # ── Marimo ──
  if [[ "$ENABLE_MARIMO" == "yes" ]]; then
    printf '\n%s\n' "$SEP"
    printf '🧩  Marimo\n\n'
    printf '  url:     http://%s:%s/?access_token=%s\n' "$marimo_host" "$MARIMO_PORT" "$MARIMO_TOKEN"
    if [[ "$PUBLIC_MARIMO" == "yes" ]]; then
      printf '  tunnel:  gcloud compute tpus tpu-vm ssh %s %s --zone=%s -- -L %s:127.0.0.1:%s\n' \
        "$ssh_target" "$project_flag" "$ssh_zone" "$MARIMO_PORT" "$MARIMO_PORT"
      printf '           http://127.0.0.1:%s/?access_token=%s\n' "$MARIMO_PORT" "$MARIMO_TOKEN"
    fi
    printf '  status:  systemctl --user status tpu-marimo.service\n'
    printf '  logs:    journalctl --user -u tpu-marimo.service -f\n'
  fi

  # ── Workspace & Monitoring ──
  printf '\n%s\n' "$SEP"
  printf '⚡  Workspace & Monitoring\n\n'
  printf '  status:    tpu-status     (view live CPU, memory, and active processes)\n'
  printf '  workspace: tpu-workspace  (starts/attaches tmux panel with dev shell and service logs)\n'

  printf '\n%s\n\n' "$SEP"
}

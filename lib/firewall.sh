#!/usr/bin/env bash
# lib/firewall.sh — GCP firewall rule helpers (unified).

detect_source_range() {
  if [[ "$PUBLIC_JUPYTER_OPEN" == "yes" ]]; then
    FIREWALL_SOURCE_RANGE="0.0.0.0/0"
    return
  fi
  if [[ "$FIREWALL_SOURCE_RANGE" != "auto" ]]; then
    return
  fi
  if [[ "$APPLY_FIREWALL" == "yes" ]]; then
    die "--apply-firewall requires explicit --firewall-source CIDR. Auto-detection from the TPU VM may detect the VM egress IP, not your laptop IP."
  fi
  local ip
  ip="$(curl -fsS --connect-timeout 2 --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    FIREWALL_SOURCE_RANGE="$ip/32"
  else
    FIREWALL_SOURCE_RANGE="<YOUR_IP_CIDR>"
  fi
}

# Print (and optionally apply) a single firewall rule.
# Usage: ensure_firewall_rule <rule_name> <port> <source_range>
ensure_firewall_rule() {
  local rule_name="$1" port="$2" source_range="$3"
  local project_flag="${GCP_PROJECT:+--project $GCP_PROJECT}"

  if [[ "$APPLY_FIREWALL" == "yes" || "$APPLY_SSH_FIREWALL" == "yes" ]]; then
    if command -v gcloud >/dev/null 2>&1; then
      log "Creating/updating firewall rule $rule_name"
      # shellcheck disable=SC2086
      if gcloud compute firewall-rules describe "$rule_name" $project_flag >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        run gcloud compute firewall-rules update "$rule_name" \
          --allow "tcp:$port" \
          --source-ranges "$source_range" \
          $project_flag
      else
        # shellcheck disable=SC2086
        run gcloud compute firewall-rules create "$rule_name" \
          --allow "tcp:$port" \
          --network default \
          --source-ranges "$source_range" \
          $project_flag
      fi
    else
      warn "gcloud not available; printing firewall command to run from your local machine or Cloud Shell."
    fi
  fi

  # Always print the command for reference.
  cat <<EOF

  gcloud compute firewall-rules create $rule_name \\
    --allow tcp:$port \\
    --network default \\
    --source-ranges $source_range${GCP_PROJECT:+ \\
    --project $GCP_PROJECT}
EOF
}

print_firewall_commands() {
  [[ "$PRINT_FIREWALL_COMMAND" == "yes" || "$APPLY_FIREWALL" == "yes" ]] || return 0
  detect_source_range

  cat <<EOF

🔥 Firewall commands
Source ranges are the client IPs allowed to connect. Current source range:

  $FIREWALL_SOURCE_RANGE

Run these from your laptop or Cloud Shell, not from the TPU VM.
EOF

  if [[ "$PUBLIC_JUPYTER" == "yes" ]]; then
    printf '\nJupyterLab firewall:\n'
    ensure_firewall_rule "allow-tpu-jupyter-$JUPYTER_PORT" "$JUPYTER_PORT" "$FIREWALL_SOURCE_RANGE"
  fi

  if [[ "$ENABLE_MARIMO" == "yes" && "$PUBLIC_MARIMO" == "yes" ]]; then
    printf '\nMarimo firewall:\n'
    ensure_firewall_rule "allow-tpu-marimo-$MARIMO_PORT" "$MARIMO_PORT" "$FIREWALL_SOURCE_RANGE"
  fi

  cat <<'EOF'

Notes:
  - 0.0.0.0/0 means public internet access.
  - Use --public-jupyter-open yes only when you intentionally want that.
  - For a private source range, pass --firewall-source <YOUR_IP>/32.
EOF
}

print_ssh_firewall_commands() {
  [[ "$GENERATE_SHARE_SSH_KEY" == "yes" ]] || return 0
  local ssh_source_range="$FIREWALL_SOURCE_RANGE"
  if [[ "$PUBLIC_SSH_OPEN" == "yes" ]]; then
    ssh_source_range="0.0.0.0/0"
  elif [[ "$ssh_source_range" == "auto" ]]; then
    ssh_source_range="<COLLABORATOR_IP_CIDR>"
  fi

  printf '\n🔑 SSH firewall\n'
  printf 'Direct SSH needs tcp:%s open unless an existing firewall rule already covers it.\n' "$SSH_PORT"
  ensure_firewall_rule "allow-tpu-ssh-$SSH_PORT" "$SSH_PORT" "$ssh_source_range"
}

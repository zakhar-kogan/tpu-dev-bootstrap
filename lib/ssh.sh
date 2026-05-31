#!/usr/bin/env bash
# lib/ssh.sh — SSH key generation and worker helper script.

generate_share_ssh_key() {
  [[ "$GENERATE_SHARE_SSH_KEY" == "yes" ]] || return 0
  log "Generating shareable SSH key"
  run mkdir -p "$(dirname "$SHARE_SSH_KEY_PATH")"
  if [[ -f "$SHARE_SSH_KEY_PATH" ]]; then
    warn "SSH key already exists: $SHARE_SSH_KEY_PATH"
  else
    run ssh-keygen -t ed25519 -N "" -C "$SHARE_SSH_USER@tpu-dev-$ENV_NAME" -f "$SHARE_SSH_KEY_PATH"
  fi
  if [[ "$DRY_RUN" != "yes" && -f "$SHARE_SSH_KEY_PATH.pub" ]]; then
    local target_home
    target_home="$(getent passwd "$SHARE_SSH_USER" 2>/dev/null | cut -d: -f6 || true)"
    if [[ -z "$target_home" ]]; then
      warn "Could not resolve home for user '$SHARE_SSH_USER'; falling back to $HOME"
      target_home="$HOME"
    fi
    local target_auth="$target_home/.ssh/authorized_keys"
    log "Adding shareable SSH public key to $target_auth"
    if [[ "$SHARE_SSH_USER" != "$USER" ]]; then
      sudo mkdir -p "$target_home/.ssh"
      sudo chmod 700 "$target_home/.ssh"
      sudo touch "$target_auth"
      sudo chmod 600 "$target_auth"
      grep -qxF "$(cat "$SHARE_SSH_KEY_PATH.pub")" "$target_auth" 2>/dev/null \
        || cat "$SHARE_SSH_KEY_PATH.pub" | sudo tee -a "$target_auth" >/dev/null
      sudo chown -R "$SHARE_SSH_USER:" "$target_home/.ssh"
    else
      mkdir -p "$target_home/.ssh"
      chmod 700 "$target_home/.ssh"
      touch "$target_auth"
      chmod 600 "$target_auth"
      grep -qxF "$(cat "$SHARE_SSH_KEY_PATH.pub")" "$target_auth" \
        || cat "$SHARE_SSH_KEY_PATH.pub" >> "$target_auth"
    fi
  fi
}

print_share_ssh_instructions() {
  [[ "$GENERATE_SHARE_SSH_KEY" == "yes" ]] || return 0
  local pubkey_file="$SHARE_SSH_KEY_PATH.pub"
  local command_file="$SHARE_SSH_KEY_PATH.add-to-tpu.sh"
  local ssh_target="${TPU_NAME:-<TPU_NAME>}"
  local ssh_zone="${GCP_ZONE:-<ZONE>}"
  local project_arg=""
  local public_key_text="<PUBLIC_KEY>"
  [[ -n "$GCP_PROJECT" ]] && project_arg=" --project=$GCP_PROJECT"
  [[ -f "$pubkey_file" ]] && public_key_text="$(cat "$pubkey_file")"
  if [[ "$DRY_RUN" != "yes" && -f "$pubkey_file" ]]; then
    cat > "$command_file" <<EOF_CMD
#!/usr/bin/env bash
set -Eeuo pipefail
gcloud compute tpus tpu-vm ssh $ssh_target$project_arg --zone=$ssh_zone --worker=all --command 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qxF "$public_key_text" ~/.ssh/authorized_keys 2>/dev/null || printf "%s\n" "$public_key_text" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
EOF_CMD
    chmod 700 "$command_file"
  fi
}

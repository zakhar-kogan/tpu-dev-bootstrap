#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.2.0"

# ── Defaults ─────────────────────────────────────────────────────────
DEFAULT_PYTHON="3.10"
DEFAULT_ENV_NAME="tpu-dev"
DEFAULT_ENV_BASE="$HOME/.local/share/tpu-dev/envs"
DEFAULT_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/tpu-dev"
DEFAULT_JUPYTER_PORT="8888"
DEFAULT_MARIMO_PORT="2718"
DEFAULT_PACKAGE_GROUPS="core,tpu,general-ds,graphs,nlp,cayley-graphs"
DEFAULT_TORCH_VERSION="2.9.0"
DEFAULT_TORCH_XLA_VERSION="2.9.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == "/" || ! -f "$SCRIPT_DIR/install.sh" ]]; then
  SCRIPT_DIR="$(pwd)"
fi

# ── Global State ─────────────────────────────────────────────────────
CONFIG_PATH=""
PYTHON_VERSION="$DEFAULT_PYTHON"
ENV_NAME="$DEFAULT_ENV_NAME"
ENV_BASE="$DEFAULT_ENV_BASE"
ENV_DIR=""
JUPYTER_PORT="$DEFAULT_JUPYTER_PORT"
MARIMO_PORT="$DEFAULT_MARIMO_PORT"
PUBLIC_JUPYTER="ask"
PUBLIC_MARIMO="ask"
ENABLE_JUPYTER="yes"
ENABLE_MARIMO="no"
CLOUDFLARE_TUNNEL="no"
APT_PACKAGES=()
PACKAGE_GROUPS="$DEFAULT_PACKAGE_GROUPS"
TORCH_VERSION="$DEFAULT_TORCH_VERSION"
TORCH_XLA_VERSION="$DEFAULT_TORCH_XLA_VERSION"
PRINT_FIREWALL_COMMAND="yes"
APPLY_FIREWALL="no"
FIREWALL_SOURCE_RANGE="0.0.0.0/0"
PUBLIC_JUPYTER_OPEN="no"
PUBLIC_SSH_OPEN="no"
APPLY_SSH_FIREWALL="no"
SSH_PORT="22"
GCP_PROJECT=""
GCP_ZONE=""
TPU_NAME=""
TPU_EXTERNAL_IP=""
GENERATE_SHARE_SSH_KEY="no"
SHARE_SSH_USER="$USER"
SHARE_SSH_KEY_PATH=""
EXTRA_PIP=()
RECREATE="no"
ASSUME_YES="no"
DRY_RUN="no"

# ── Source Library Modules ───────────────────────────────────────────
for _lib in ui config env packages services firewall ssh summary; do
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/lib/$_lib.sh"
done

# ── Usage ────────────────────────────────────────────────────────────
usage() {
  cat <<'USAGE'
TPU Dev Bootstrap installer.

Usage:
  curl -fsSL .../bootstrap.sh | bash -s -- [options]
  ./install.sh [options]

Options:
  --config PATH_OR_URL             Load .env config file.
  --python VERSION                 Python version for uv venv. Default: 3.10.
  --env-name NAME                  Environment/kernel name. Default: tpu-dev.
  --env-dir PATH                   Exact venv parent directory.
  --jupyter-port PORT              JupyterLab port. Default: 8888.
  --jupyter yes|no                 Install and start JupyterLab. Default: yes.
  --public-jupyter yes|no|ask      Bind Jupyter to 0.0.0.0 or localhost. Default: ask.
  --marimo yes|no                  Install and start Marimo service. Default: no.
  --marimo-port PORT               Marimo port. Default: 2718.
  --public-marimo yes|no|ask       Bind Marimo to 0.0.0.0 or localhost. Default: ask.
  --cloudflare-quick-tunnel yes|no Print cloudflared tunnel command. Default: no.
  --package-groups LIST            Comma list of groups (see packages/*.txt).
  --extra-pip PACKAGE              Extra pip spec. Repeatable.
  --apt-packages PKG               Extra apt package. Repeatable.
  --torch-version VERSION          Default: 2.9.0.
  --torch-xla-version VERSION      Default: 2.9.0.
  --firewall-source CIDR           Source range for firewall rules. Default: 0.0.0.0/0.
  --public-jupyter-open yes|no     (Deprecated, now default.) Use 0.0.0.0/0 for Jupyter.
  --public-ssh-open yes|no         SSH firewall with 0.0.0.0/0. Default: no.
  --ssh-port PORT                  SSH port for firewall. Default: 22.
  --print-firewall-command yes|no  Print gcloud firewall command. Default: yes.
  --apply-firewall yes|no          Create/update firewall rule. Default: no.
  --apply-ssh-firewall yes|no      Create/update SSH firewall rule. Default: no.
  --project PROJECT                Override GCP project.
  --zone ZONE                      Override TPU zone.
  --tpu-name NAME                  Override TPU VM name.
  --external-ip IP                 Override external IP.
  --generate-share-ssh-key yes|no  Generate a shareable SSH keypair. Default: no.
  --share-ssh-user USER            Linux user for shared SSH key. Default: current.
  --share-ssh-key-path PATH        SSH key path. Default: ~/.ssh/tpu-dev-<env-name>.
  --recreate                       Delete and recreate the venv.
  --yes                            Accept defaults without prompts.
  --dry-run                        Print actions without executing.
  --help                           Show help.
USAGE
}

# ── Load Saved Config ────────────────────────────────────────────────
CONFIG_HOME="$DEFAULT_CONFIG_HOME"
SECRETS_FILE="$CONFIG_HOME/secrets.env"
load_saved_config "$SECRETS_FILE"

# ── Parse CLI Arguments ──────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_PATH="${2:?}"; shift 2 ;;
    --python) PYTHON_VERSION="${2:?}"; shift 2 ;;
    --env-name) ENV_NAME="${2:?}"; shift 2 ;;
    --env-dir) ENV_DIR="${2:?}"; shift 2 ;;
    --jupyter-port) JUPYTER_PORT="${2:?}"; shift 2 ;;
    --jupyter) ENABLE_JUPYTER="$(parse_bool "${2:?}")"; shift 2 ;;
    --public-jupyter) PUBLIC_JUPYTER="$(parse_bool "${2:?}")"; shift 2 ;;
    --marimo) ENABLE_MARIMO="$(parse_bool "${2:?}")"; shift 2 ;;
    --marimo-port) MARIMO_PORT="${2:?}"; shift 2 ;;
    --public-marimo) PUBLIC_MARIMO="$(parse_bool "${2:?}")"; shift 2 ;;
    --cloudflare-quick-tunnel) CLOUDFLARE_TUNNEL="$(parse_bool "${2:?}")"; shift 2 ;;
    --package-groups) PACKAGE_GROUPS="${2:?}"; shift 2 ;;
    --extra-pip) EXTRA_PIP+=("${2:?}"); shift 2 ;;
    --apt-packages) APT_PACKAGES+=("${2:?}"); shift 2 ;;
    --torch-version) TORCH_VERSION="${2:?}"; shift 2 ;;
    --torch-xla-version) TORCH_XLA_VERSION="${2:?}"; shift 2 ;;
    --firewall-source) FIREWALL_SOURCE_RANGE="${2:?}"; shift 2 ;;
    --public-jupyter-open) PUBLIC_JUPYTER_OPEN="$(parse_bool "${2:?}")"; shift 2 ;;
    --public-ssh-open) PUBLIC_SSH_OPEN="$(parse_bool "${2:?}")"; shift 2 ;;
    --ssh-port) SSH_PORT="${2:?}"; shift 2 ;;
    --print-firewall-command) PRINT_FIREWALL_COMMAND="$(parse_bool "${2:?}")"; shift 2 ;;
    --apply-firewall) APPLY_FIREWALL="$(parse_bool "${2:?}")"; shift 2 ;;
    --apply-ssh-firewall) APPLY_SSH_FIREWALL="$(parse_bool "${2:?}")"; shift 2 ;;
    --project) GCP_PROJECT="${2:?}"; shift 2 ;;
    --zone) GCP_ZONE="${2:?}"; shift 2 ;;
    --tpu-name) TPU_NAME="${2:?}"; shift 2 ;;
    --external-ip) TPU_EXTERNAL_IP="${2:?}"; shift 2 ;;
    --generate-share-ssh-key) GENERATE_SHARE_SSH_KEY="$(parse_bool "${2:?}")"; shift 2 ;;
    --share-ssh-user) SHARE_SSH_USER="${2:?}"; shift 2 ;;
    --share-ssh-key-path) SHARE_SSH_KEY_PATH="${2:?}"; shift 2 ;;
    --recreate) RECREATE="yes"; shift ;;
    --yes) ASSUME_YES="yes"; shift ;;
    --dry-run) DRY_RUN="yes"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# ── Apply Config File ───────────────────────────────────────────────
if [[ -n "$CONFIG_PATH" ]]; then
  CONFIG_FILE="$(download_config "$CONFIG_PATH")"
  apply_config "$CONFIG_FILE"
fi

# ── Interactive Prompts ──────────────────────────────────────────────
if have_tty && [[ "$ASSUME_YES" != "yes" ]]; then
  log "Interactive setup"
  PYTHON_VERSION="$(prompt_default "Python version" "$PYTHON_VERSION")"
  ENV_NAME="$(prompt_default "Environment/kernel name" "$ENV_NAME")"
  JUPYTER_PORT="$(prompt_default "JupyterLab port" "$JUPYTER_PORT")"
  if [[ "$PUBLIC_JUPYTER" == "ask" ]]; then
    PUBLIC_JUPYTER="$(prompt_yes_no "Bind Jupyter publicly with token auth" "yes")"
  fi
  ENABLE_MARIMO="$(prompt_yes_no "Install and run Marimo" "$ENABLE_MARIMO")"
  if [[ "$ENABLE_MARIMO" == "yes" ]]; then
    MARIMO_PORT="$(prompt_default "Marimo port" "$MARIMO_PORT")"
    if [[ "$PUBLIC_MARIMO" == "ask" ]]; then
      PUBLIC_MARIMO="$(prompt_yes_no "Bind Marimo publicly with token auth" "yes")"
    fi
  fi
  CLOUDFLARE_TUNNEL="$(prompt_yes_no "Print Cloudflare quick tunnel command" "$CLOUDFLARE_TUNNEL")"
  GENERATE_SHARE_SSH_KEY="$(prompt_yes_no "Generate shareable SSH keypair" "$GENERATE_SHARE_SSH_KEY")"
  select_groups
fi

# ── Resolve Defaults ─────────────────────────────────────────────────
[[ "$PUBLIC_JUPYTER" == "ask" ]] && PUBLIC_JUPYTER="yes"
[[ "$PUBLIC_MARIMO" == "ask" ]] && PUBLIC_MARIMO="$PUBLIC_JUPYTER"
ENV_BASE="${ENV_BASE/#\~/$HOME}"
ENV_DIR="${ENV_DIR/#\~/$HOME}"
[[ -z "$ENV_DIR" ]] && ENV_DIR="$ENV_BASE/$ENV_NAME"
[[ -z "$SHARE_SSH_KEY_PATH" ]] && SHARE_SSH_KEY_PATH="$HOME/.ssh/tpu-dev-$ENV_NAME"
SHARE_SSH_KEY_PATH="${SHARE_SSH_KEY_PATH/#\~/$HOME}"
VENV_DIR="$ENV_DIR/.venv"
CONFIG_HOME="$DEFAULT_CONFIG_HOME"
SECRETS_FILE="$CONFIG_HOME/secrets.env"
LOG_DIR="$HOME/.local/state/tpu-dev"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
MARIMO_TOKEN=""

IFS=',' read -r -a GROUPS_ARRAY <<< "$PACKAGE_GROUPS"

# ── Main ─────────────────────────────────────────────────────────────
main() {
  require_linux
  detect_gcp_metadata
  install_system_deps
  install_uv
  create_env
  install_packages
  generate_secret
  register_kernel
  install_jupyter_service
  install_marimo_service
  install_helper_scripts
  generate_share_ssh_key
  print_firewall_commands
  print_ssh_firewall_commands
  print_cloudflare
  print_share_ssh_instructions
  print_summary
}

main "$@"

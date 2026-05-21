#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.1.0"

DEFAULT_PYTHON="3.10"
DEFAULT_ENV_NAME="tpu-dev"
DEFAULT_ENV_BASE="$HOME/.local/share/tpu-dev/envs"
DEFAULT_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/tpu-dev"
DEFAULT_JUPYTER_PORT="8888"
DEFAULT_MARIMO_PORT="2718"
DEFAULT_PACKAGE_GROUPS="core,tpu,research,viz"
DEFAULT_CAYLEYPY_SOURCE="git"
DEFAULT_CAYLEYPY_GIT="git+https://github.com/cayleypy/cayleypy/"
DEFAULT_CAYLEYPY_PIP="cayleypy"
DEFAULT_TORCH_VERSION="2.9.0"
DEFAULT_TORCH_XLA_VERSION="2.9.0"
METADATA_BASE="http://metadata.google.internal/computeMetadata/v1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == "/" || ! -f "$SCRIPT_DIR/install.sh" ]]; then
  SCRIPT_DIR="$(pwd)"
fi

CONFIG_PATH=""
PYTHON_VERSION="$DEFAULT_PYTHON"
ENV_NAME="$DEFAULT_ENV_NAME"
ENV_BASE="$DEFAULT_ENV_BASE"
ENV_DIR=""
JUPYTER_PORT="$DEFAULT_JUPYTER_PORT"
MARIMO_PORT="$DEFAULT_MARIMO_PORT"
PUBLIC_JUPYTER="ask"
ENABLE_JUPYTER="yes"
ENABLE_MARIMO="no"
CLOUDFLARE_TUNNEL="no"
PACKAGE_GROUPS="$DEFAULT_PACKAGE_GROUPS"
CAYLEYPY_SOURCE="$DEFAULT_CAYLEYPY_SOURCE"
CAYLEYPY_GIT="$DEFAULT_CAYLEYPY_GIT"
CAYLEYPY_PIP="$DEFAULT_CAYLEYPY_PIP"
TORCH_VERSION="$DEFAULT_TORCH_VERSION"
TORCH_XLA_VERSION="$DEFAULT_TORCH_XLA_VERSION"
PRINT_FIREWALL_COMMAND="yes"
APPLY_FIREWALL="no"
FIREWALL_SOURCE_RANGE="auto"
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

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
TPU Dev Bootstrap installer.

Usage:
  curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/install.sh | bash -s -- [options]
  ./install.sh [options]

Options:
  --config PATH_OR_URL             Load flat YAML config.
  --python VERSION                 Python version for uv venv. Default: 3.10.
  --env-name NAME                  Environment/kernel name. Default: tpu-dev.
  --env-dir PATH                   Exact venv parent directory.
  --jupyter-port PORT              JupyterLab port. Default: 8888.
  --jupyter yes|no                 Install and start JupyterLab. Default: yes.
  --public-jupyter yes|no|ask      Bind Jupyter to 0.0.0.0 or localhost. Default: ask.
  --marimo yes|no                  Install and start Marimo service. Default: no.
  --marimo-port PORT               Marimo port. Default: 2718.
  --cloudflare-quick-tunnel yes|no Start a quick cloudflared tunnel command. Default: no.
  --package-groups LIST            Comma list: core,tpu,research,viz,marimo,ui-demos,jax,dev.
  --extra-pip PACKAGE              Extra pip spec. Repeatable.
  --cayleypy-source git|pip|none   Default: git.
  --cayleypy-git SPEC              Default: git+https://github.com/cayleypy/cayleypy/
  --cayleypy-pip SPEC              Default: cayleypy.
  --torch-version VERSION          Default: 2.9.0.
  --torch-xla-version VERSION      Default: 2.9.0.
  --firewall-source CIDR|auto      Source range for printed/applied firewall rule. Default: auto.
  --print-firewall-command yes|no  Print gcloud firewall command. Default: yes.
  --apply-firewall yes|no          Create/update firewall rule. Default: no.
  --project PROJECT                Override detected GCP project for commands.
  --zone ZONE                      Override detected TPU zone for commands.
  --tpu-name NAME                  Override detected TPU VM name for commands.
  --external-ip IP                 Override detected external IP for URL.
  --generate-share-ssh-key yes|no  Generate a shareable SSH keypair. Default: no.
  --share-ssh-user USER            Linux username for the shared SSH key. Default: current user.
  --share-ssh-key-path PATH        SSH key path. Default: ~/.ssh/tpu-dev-<env-name>.
  --recreate                       Delete and recreate the target venv.
  --yes                            Accept defaults without prompts.
  --dry-run                        Print actions without changing the machine.
  --help                           Show help.
USAGE
}

parse_bool() {
  case "${1,,}" in
    yes|y|true|1|on) printf yes ;;
    no|n|false|0|off) printf no ;;
    ask) printf ask ;;
    *) die "Expected yes/no/ask, got: $1" ;;
  esac
}

have_tty() { [[ -r /dev/tty && -w /dev/tty ]]; }

prompt_default() {
  local name="$1" default="$2" answer
  if [[ "$ASSUME_YES" == "yes" || ! -r /dev/tty ]]; then
    printf '%s' "$default"
    return
  fi
  printf '%s [%s]: ' "$name" "$default" > /dev/tty
  read -r answer < /dev/tty || answer=""
  printf '%s' "${answer:-$default}"
}

prompt_yes_no() {
  local name="$1" default="$2" answer suffix
  if [[ "$ASSUME_YES" == "yes" || ! -r /dev/tty ]]; then
    printf '%s' "$default"
    return
  fi
  suffix="y/N"
  [[ "$default" == "yes" ]] && suffix="Y/n"
  printf '%s [%s]: ' "$name" "$suffix" > /dev/tty
  read -r answer < /dev/tty || answer=""
  answer="${answer:-$default}"
  parse_bool "$answer"
}

run() {
  if [[ "$DRY_RUN" == "yes" ]]; then
    printf 'DRY-RUN: %q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

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
  local config_file="$1" rendered
  rendered="$(python3 - "$config_file" <<'PY'
import ast
import shlex
import sys

path = sys.argv[1]
data = {}
current = None

def parse_scalar(s):
    s = s.strip()
    if not s:
        return ""
    if s[0:1] in "'\"" and s[-1:] == s[0]:
        try:
            return ast.literal_eval(s)
        except Exception:
            return s[1:-1]
    low = s.lower()
    if low in {"true", "yes", "on"}:
        return "yes"
    if low in {"false", "no", "off"}:
        return "no"
    if s.startswith("[") and s.endswith("]"):
        try:
            return ast.literal_eval(s)
        except Exception:
            return [x.strip() for x in s[1:-1].split(",") if x.strip()]
    return s

for raw in open(path, encoding="utf-8"):
    line = raw.split("#", 1)[0].rstrip()
    if not line.strip():
        continue
    if line.startswith("  - ") and current:
        data.setdefault(current, []).append(parse_scalar(line[4:]))
        continue
    if ":" in line and not line.startswith(" "):
        key, value = line.split(":", 1)
        key = key.strip().replace("-", "_")
        value = value.strip()
        current = key
        if value:
            data[key] = parse_scalar(value)
        else:
            data[key] = []

mapping = {
    "python_version": "PYTHON_VERSION",
    "env_name": "ENV_NAME",
    "env_base": "ENV_BASE",
    "env_dir": "ENV_DIR",
    "jupyter_port": "JUPYTER_PORT",
    "marimo_port": "MARIMO_PORT",
    "public_jupyter": "PUBLIC_JUPYTER",
    "enable_jupyter": "ENABLE_JUPYTER",
    "enable_marimo": "ENABLE_MARIMO",
    "cloudflare_quick_tunnel": "CLOUDFLARE_TUNNEL",
    "package_groups": "PACKAGE_GROUPS",
    "cayleypy_source": "CAYLEYPY_SOURCE",
    "cayleypy_git": "CAYLEYPY_GIT",
    "cayleypy_pip": "CAYLEYPY_PIP",
    "torch_version": "TORCH_VERSION",
    "torch_xla_version": "TORCH_XLA_VERSION",
}

for key, shell_key in mapping.items():
    if key not in data:
        continue
    value = data[key]
    if isinstance(value, list):
        value = ",".join(str(x) for x in value)
    print(f"{shell_key}={shlex.quote(str(value))}")

extra = data.get("extra_pip", [])
if isinstance(extra, str):
    extra = [extra]
for item in extra:
    print(f"EXTRA_PIP+=({shlex.quote(str(item))})")
PY
)"
  eval "$rendered"
}

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
    --cloudflare-quick-tunnel) CLOUDFLARE_TUNNEL="$(parse_bool "${2:?}")"; shift 2 ;;
    --package-groups) PACKAGE_GROUPS="${2:?}"; shift 2 ;;
    --extra-pip) EXTRA_PIP+=("${2:?}"); shift 2 ;;
    --cayleypy-source) CAYLEYPY_SOURCE="${2:?}"; shift 2 ;;
    --cayleypy-git) CAYLEYPY_GIT="${2:?}"; shift 2 ;;
    --cayleypy-pip) CAYLEYPY_PIP="${2:?}"; shift 2 ;;
    --torch-version) TORCH_VERSION="${2:?}"; shift 2 ;;
    --torch-xla-version) TORCH_XLA_VERSION="${2:?}"; shift 2 ;;
    --firewall-source) FIREWALL_SOURCE_RANGE="${2:?}"; shift 2 ;;
    --print-firewall-command) PRINT_FIREWALL_COMMAND="$(parse_bool "${2:?}")"; shift 2 ;;
    --apply-firewall) APPLY_FIREWALL="$(parse_bool "${2:?}")"; shift 2 ;;
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

if [[ -n "$CONFIG_PATH" ]]; then
  CONFIG_FILE="$(download_config "$CONFIG_PATH")"
  apply_config "$CONFIG_FILE"
fi

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
  fi
  CLOUDFLARE_TUNNEL="$(prompt_yes_no "Start/print Cloudflare quick tunnel" "$CLOUDFLARE_TUNNEL")"
fi

[[ "$PUBLIC_JUPYTER" == "ask" ]] && PUBLIC_JUPYTER="yes"
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

IFS=',' read -r -a GROUPS_ARRAY <<< "$PACKAGE_GROUPS"

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

detect_source_range() {
  if [[ "$FIREWALL_SOURCE_RANGE" != "auto" ]]; then
    return
  fi
  if [[ "$APPLY_FIREWALL" == "yes" ]]; then
    die "--apply-firewall requires explicit --firewall-source CIDR. Auto-detection from the TPU VM may detect the VM egress IP, not your laptop IP."
  fi
  local ip
  ip="$(curl -fsS --connect-timeout 2 --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && FIREWALL_SOURCE_RANGE="$ip/32" || FIREWALL_SOURCE_RANGE="<YOUR_IP_CIDR>"
}

install_system_deps() {
  log "Installing system dependencies"
  if command -v apt-get >/dev/null 2>&1; then
    run sudo apt-get update
    run sudo apt-get install -y ca-certificates curl git build-essential jq openssl
  else
    warn "apt-get not found; install curl/git/build tools manually if missing."
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
    log "Reusing existing venv"
  fi
}

group_packages() {
  local group="$1"
  case "$group" in
    core)
      printf '%s\n' pip setuptools wheel ipykernel jupyterlab jupyter-server jupyterlab-git
      ;;
    tpu)
      printf '%s\n' numpy "torch==$TORCH_VERSION" "torch_xla[tpu]==$TORCH_XLA_VERSION"
      ;;
    research)
      printf '%s\n' pandas scipy numba transformers datasets accelerate networkx tqdm rich
      ;;
    viz)
      printf '%s\n' matplotlib seaborn
      ;;
    marimo)
      printf '%s\n' marimo
      ;;
    ui-demos)
      printf '%s\n' streamlit plotly dash panel bokeh holoviews hvplot
      ;;
    jax)
      printf '%s\n' jax jaxlib
      ;;
    dev)
      printf '%s\n' ruff pytest black pre-commit
      ;;
    "")
      ;;
    *)
      warn "Unknown package group: $group"
      ;;
  esac
}

install_packages() {
  local packages=()
  log "Installing Python package groups: $PACKAGE_GROUPS"
  for group in "${GROUPS_ARRAY[@]}"; do
    while IFS= read -r pkg; do
      [[ -n "$pkg" ]] && packages+=("$pkg")
    done < <(group_packages "$group")
  done
  if [[ "$ENABLE_MARIMO" == "yes" && ",$PACKAGE_GROUPS," != *",marimo,"* ]]; then
    packages+=("marimo")
  fi
  case "$CAYLEYPY_SOURCE" in
    git) packages+=("$CAYLEYPY_GIT") ;;
    pip) packages+=("$CAYLEYPY_PIP") ;;
    none) ;;
    *) die "Unknown cayleypy source: $CAYLEYPY_SOURCE" ;;
  esac
  packages+=("${EXTRA_PIP[@]}")
  ((${#packages[@]} > 0)) || return 0
  run uv pip install --python "$VENV_DIR/bin/python" "${packages[@]}" -f https://storage.googleapis.com/libtpu-releases/index.html
}

generate_secret() {
  run mkdir -p "$CONFIG_HOME" "$LOG_DIR"
  if [[ -f "$SECRETS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SECRETS_FILE"
  fi
  if [[ -z "${JUPYTER_TOKEN:-}" ]]; then
    JUPYTER_TOKEN="$("$VENV_DIR/bin/python" - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)"
  fi
  if [[ "$DRY_RUN" != "yes" ]]; then
    umask 077
    {
      printf 'JUPYTER_TOKEN=%q\n' "$JUPYTER_TOKEN"
      printf 'JUPYTER_PORT=%q\n' "$JUPYTER_PORT"
      printf 'MARIMO_PORT=%q\n' "$MARIMO_PORT"
      printf 'ENV_DIR=%q\n' "$ENV_DIR"
    } > "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE"
  fi
}

write_service() {
  local name="$1" file="$2" content="$3"
  run mkdir -p "$SYSTEMD_USER_DIR"
  if [[ "$DRY_RUN" == "yes" ]]; then
    echo "DRY-RUN: write $file"
  else
    printf '%s\n' "$content" > "$file"
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
  local service
  service="[Unit]
Description=TPU Dev JupyterLab
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$ENV_DIR
Environment=PATH=$VENV_DIR/bin:$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$VENV_DIR/bin/jupyter lab --ip=$bind_ip --port=$JUPYTER_PORT --no-browser --ServerApp.token=$JUPYTER_TOKEN --ServerApp.password= --ServerApp.open_browser=False --ServerApp.allow_remote_access=$allow_remote
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target"
  write_service "jupyter" "$SYSTEMD_USER_DIR/tpu-jupyter.service" "$service"
  if [[ "$DRY_RUN" != "yes" ]]; then
    systemctl --user daemon-reload
    systemctl --user enable --now tpu-jupyter.service
    loginctl enable-linger "$USER" >/dev/null 2>&1 || true
  fi
}

install_marimo_service() {
  [[ "$ENABLE_MARIMO" == "yes" ]] || return 0
  log "Installing Marimo user service"
  local service
  service="[Unit]
Description=TPU Dev Marimo
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$ENV_DIR
Environment=PATH=$VENV_DIR/bin:$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$VENV_DIR/bin/marimo edit --host 127.0.0.1 --port $MARIMO_PORT --headless
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target"
  write_service "marimo" "$SYSTEMD_USER_DIR/tpu-marimo.service" "$service"
  if [[ "$DRY_RUN" != "yes" ]]; then
    systemctl --user daemon-reload
    systemctl --user enable --now tpu-marimo.service
  fi
}

register_kernel() {
  log "Registering Jupyter kernel"
  run "$VENV_DIR/bin/python" -m ipykernel install --user --name "$ENV_NAME" --display-name "TPU Dev ($ENV_NAME)"
}

print_firewall_commands() {
  [[ "$PUBLIC_JUPYTER" == "yes" ]] || return 0
  [[ "$PRINT_FIREWALL_COMMAND" == "yes" || "$APPLY_FIREWALL" == "yes" ]] || return 0
  detect_source_range
  local rule_name="allow-tpu-jupyter-$JUPYTER_PORT"
  local command=(
    gcloud compute firewall-rules create "$rule_name"
    --allow "tcp:$JUPYTER_PORT"
    --network default
    --source-ranges "$FIREWALL_SOURCE_RANGE"
  )
  if [[ -n "$GCP_PROJECT" ]]; then
    command+=(--project "$GCP_PROJECT")
  fi
  if [[ "$APPLY_FIREWALL" == "yes" ]]; then
    log "Creating firewall rule $rule_name"
    if gcloud compute firewall-rules describe "$rule_name" ${GCP_PROJECT:+--project "$GCP_PROJECT"} >/dev/null 2>&1; then
      run gcloud compute firewall-rules update "$rule_name" \
        --allow "tcp:$JUPYTER_PORT" \
        --source-ranges "$FIREWALL_SOURCE_RANGE" \
        ${GCP_PROJECT:+--project "$GCP_PROJECT"}
    else
      run "${command[@]}"
    fi
  fi
  cat <<EOF

Firewall source ranges are the client IPs allowed to connect to public Jupyter.
If this script runs on the TPU VM, auto-detection may show the TPU VM egress IP,
not your laptop IP. Override it with --firewall-source <YOUR_IP>/32 when needed.

Suggested source range:

  $FIREWALL_SOURCE_RANGE

To allow public Jupyter access, run from your local machine or Cloud Shell:

  gcloud compute firewall-rules create $rule_name \\
    --allow tcp:$JUPYTER_PORT \\
    --network default \\
    --source-ranges $FIREWALL_SOURCE_RANGE${GCP_PROJECT:+ \\
    --project $GCP_PROJECT}

Prefer a narrow source range. Avoid 0.0.0.0/0 unless this is temporary.
EOF
}

print_cloudflare() {
  [[ "$CLOUDFLARE_TUNNEL" == "yes" ]] || return 0
  if ! command -v cloudflared >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1 && have_tty; then
      if [[ "$(prompt_yes_no "Install cloudflared .deb from GitHub releases" "no")" == "yes" ]]; then
        local arch deb
        arch="$(dpkg --print-architecture)"
        case "$arch" in
          amd64|arm64) ;;
          *) warn "Unsupported cloudflared architecture for automatic install: $arch" ;;
        esac
        if [[ "$arch" == "amd64" || "$arch" == "arm64" ]]; then
          deb="/tmp/cloudflared-linux-$arch.deb"
          run curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$arch.deb" -o "$deb"
          run sudo apt-get install -y "$deb"
        fi
      fi
    fi
  fi
  cat <<EOF

Cloudflare quick tunnel:
  cloudflared tunnel --url http://127.0.0.1:$JUPYTER_PORT
EOF
  if command -v cloudflared >/dev/null 2>&1 && have_tty; then
    if [[ "$(prompt_yes_no "Start Cloudflare quick tunnel now" "no")" == "yes" ]]; then
      run cloudflared tunnel --url "http://127.0.0.1:$JUPYTER_PORT"
    fi
  else
    warn "cloudflared not found. Install it to use quick tunnels."
  fi
}

generate_share_ssh_key() {
  [[ "$GENERATE_SHARE_SSH_KEY" == "yes" ]] || return 0
  log "Generating shareable SSH key"
  run mkdir -p "$(dirname "$SHARE_SSH_KEY_PATH")"
  if [[ -f "$SHARE_SSH_KEY_PATH" ]]; then
    warn "SSH key already exists: $SHARE_SSH_KEY_PATH"
  else
    run ssh-keygen -t ed25519 -N "" -C "$SHARE_SSH_USER@tpu-dev-$ENV_NAME" -f "$SHARE_SSH_KEY_PATH"
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
  if [[ -f "$pubkey_file" ]]; then
    public_key_text="$(cat "$pubkey_file")"
  fi
  if [[ "$DRY_RUN" != "yes" && -f "$pubkey_file" ]]; then
    cat > "$command_file" <<EOF_CMD
#!/usr/bin/env bash
set -Eeuo pipefail
gcloud compute tpus tpu-vm ssh $ssh_target$project_arg --zone=$ssh_zone --worker=all --command 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qxF "$public_key_text" ~/.ssh/authorized_keys 2>/dev/null || printf "%s\n" "$public_key_text" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
EOF_CMD
    chmod 700 "$command_file"
  fi
  cat <<EOF

Shareable SSH key:
  private key: $SHARE_SSH_KEY_PATH
  public key:  $pubkey_file
  add command: $command_file

To authorize this key on the TPU VM, run:

  $command_file

Then someone with the private key can connect with:

  gcloud compute tpus tpu-vm ssh $ssh_target$project_arg --zone=$ssh_zone --ssh-key-file=$SHARE_SSH_KEY_PATH

Share the private key only with people you trust. Remove the matching line from
~/.ssh/authorized_keys on the TPU VM to revoke access.
EOF
}

print_summary() {
  local host="127.0.0.1"
  if [[ "$PUBLIC_JUPYTER" == "yes" ]]; then
    host="${TPU_EXTERNAL_IP:-<TPU_EXTERNAL_IP>}"
  fi
  local ssh_target="${TPU_NAME:-<TPU_NAME>}"
  local ssh_zone="${GCP_ZONE:-<ZONE>}"
  local project_arg=""
  [[ -n "$GCP_PROJECT" ]] && project_arg=" --project=$GCP_PROJECT"
  cat <<EOF

Done.

Environment:
  $ENV_DIR

JupyterLab:
  systemctl --user status tpu-jupyter.service
  journalctl --user -u tpu-jupyter.service -f
  http://$host:$JUPYTER_PORT/lab?token=$JUPYTER_TOKEN

Token file:
  $SECRETS_FILE

SSH tunnel access:
  gcloud compute tpus tpu-vm ssh $ssh_target$project_arg --zone=$ssh_zone -- -L $JUPYTER_PORT:127.0.0.1:$JUPYTER_PORT
  http://127.0.0.1:$JUPYTER_PORT/lab?token=$JUPYTER_TOKEN

Remote Jupyter kernel:
  Use the Jupyter server URL above in VS Code/Jupyter and select kernel "TPU Dev ($ENV_NAME)".
EOF
}

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
  generate_share_ssh_key
  print_firewall_commands
  print_cloudflare
  print_share_ssh_instructions
  print_summary
}

main "$@"

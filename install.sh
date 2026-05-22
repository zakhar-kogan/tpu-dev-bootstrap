#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.1.0"

DEFAULT_PYTHON="3.10"
DEFAULT_ENV_NAME="tpu-dev"
DEFAULT_ENV_BASE="$HOME/.local/share/tpu-dev/envs"
DEFAULT_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/tpu-dev"
DEFAULT_JUPYTER_PORT="8888"
DEFAULT_MARIMO_PORT="2718"
DEFAULT_PACKAGE_GROUPS="core,tpu,general-ds,graphs,nlp,cayley-graphs"
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
PUBLIC_MARIMO="ask"
ENABLE_JUPYTER="yes"
ENABLE_MARIMO="no"
CLOUDFLARE_TUNNEL="no"
APT_PACKAGES=()
PACKAGE_GROUPS="$DEFAULT_PACKAGE_GROUPS"
CAYLEYPY_SOURCE="$DEFAULT_CAYLEYPY_SOURCE"
CAYLEYPY_GIT="$DEFAULT_CAYLEYPY_GIT"
CAYLEYPY_PIP="$DEFAULT_CAYLEYPY_PIP"
TORCH_VERSION="$DEFAULT_TORCH_VERSION"
TORCH_XLA_VERSION="$DEFAULT_TORCH_XLA_VERSION"
PRINT_FIREWALL_COMMAND="yes"
APPLY_FIREWALL="no"
FIREWALL_SOURCE_RANGE="auto"
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
EXTRA_INTERACTIVE_PACKAGES=()
RECREATE="no"
ASSUME_YES="no"
DRY_RUN="no"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

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
  --public-marimo yes|no|ask       Bind Marimo to 0.0.0.0 or localhost. Default: ask (when Marimo enabled).
  --cloudflare-quick-tunnel yes|no Start a quick cloudflared tunnel command. Default: no.
  --package-groups LIST            Comma list of: core, tpu, general-ds, graphs, nlp, llms, graphml, cayley-graphs, uis, dev.
  --extra-pip PACKAGE              Extra pip spec. Repeatable.
  --apt-packages PKG               Extra apt package to install. Repeatable.
  --cayleypy-source git|pip|none   Default: git.
  --cayleypy-git SPEC              Default: git+https://github.com/cayleypy/cayleypy/
  --cayleypy-pip SPEC              Default: cayleypy.
  --torch-version VERSION          Default: 2.9.0.
  --torch-xla-version VERSION      Default: 2.9.0.
  --firewall-source CIDR|auto      Source range for printed/applied firewall rule. Default: auto.
  --public-jupyter-open yes|no     Use 0.0.0.0/0 source range for public Jupyter. Default: no.
  --public-ssh-open yes|no         Print SSH firewall rule with 0.0.0.0/0. Default: no.
  --ssh-port PORT                  SSH port for firewall and plain ssh command. Default: 22.
  --print-firewall-command yes|no  Print gcloud firewall command. Default: yes.
  --apply-firewall yes|no          Create/update firewall rule. Default: no.
  --apply-ssh-firewall yes|no      Create/update tcp:22 firewall rule. Default: no.
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

interactive_checkbox_menu() {
  local prompt="$1"
  shift
  local raw_options=("$@")
  
  local keys=()
  local defaults=()
  local desc=()
  local selections=()
  
  local num_opts=${#raw_options[@]}
  for ((i=0; i<num_opts; i++)); do
    IFS='|' read -r k d des <<< "${raw_options[i]}"
    keys[i]="$k"
    defaults[i]="$d"
    desc[i]="$des"
    if [[ "$d" == "yes" ]]; then
      selections[i]=1
    else
      selections[i]=0
    fi
  done
  
  local active=0
  local key=""
  
  # Hide cursor, restore on exit
  tput civis >/dev/tty 2>/dev/null || printf "\033[?25l" >/dev/tty
  trap 'tput cnorm >/dev/tty 2>/dev/null || printf "\033[?25h" >/dev/tty' EXIT
  
  local active_print_done=0
  
  print_menu() {
    if (( active_print_done > 0 )); then
      printf "\033[%dA" "$num_opts" >/dev/tty
    fi
    for ((i=0; i<num_opts; i++)); do
      local checkbox="[ ]"
      if (( selections[i] == 1 )); then
        checkbox="[\033[1;32mx\033[0m]"
      fi
      
      if (( i == active )); then
        printf " \033[1;36m>\033[0m %b \033[1m%-14s\033[0m - \033[36m%s\033[0m\033[K\n" "$checkbox" "${keys[i]}" "${desc[i]}" >/dev/tty
      else
        printf "   %b %-14s - %s\033[K\n" "$checkbox" "${keys[i]}" "${desc[i]}" >/dev/tty
      fi
    done
    active_print_done=1
  }
  
  printf "\033[1;34m==>\033[0m \033[1m%s\033[0m\n" "$prompt" >/dev/tty
  printf "    Use \033[1m↑/↓\033[0m (or \033[1mj/k\033[0m) to navigate, \033[1mSpace\033[0m to toggle, \033[1mEnter\033[0m to confirm.\n" >/dev/tty
  
  print_menu
  
  while true; do
    read -r -s -n 1 key < /dev/tty 2>/dev/null || true
    
    if [[ "$key" == $'\e' ]]; then
      read -r -s -n 2 -t 0.1 key < /dev/tty 2>/dev/null || true
      if [[ "$key" == "[A" ]]; then
        if (( active > 0 )); then
          (( active-- ))
          print_menu
        fi
      elif [[ "$key" == "[B" ]]; then
        if (( active < num_opts - 1 )); then
          (( active++ ))
          print_menu
        fi
      fi
    elif [[ "$key" == "k" ]]; then
      if (( active > 0 )); then
        (( active-- ))
        print_menu
      fi
    elif [[ "$key" == "j" ]]; then
      if (( active < num_opts - 1 )); then
        (( active++ ))
        print_menu
      fi
    elif [[ "$key" == " " ]]; then
      if (( selections[active] == 1 )); then
        selections[active]=0
      else
        selections[active]=1
      fi
      print_menu
    elif [[ "$key" == "" ]]; then
      break
    fi
  done
  
  tput cnorm >/dev/tty 2>/dev/null || printf "\033[?25h" >/dev/tty
  trap - EXIT
  
  local out=""
  for ((i=0; i<num_opts; i++)); do
    if (( selections[i] == 1 )); then
      if [[ -z "$out" ]]; then
        out="${keys[i]}"
      else
        out="$out,${keys[i]}"
      fi
    fi
  done
  echo "$out"
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
# Load previously configured ports if available to use as defaults
CONFIG_HOME="$DEFAULT_CONFIG_HOME"
SECRETS_FILE="$CONFIG_HOME/secrets.env"
if [[ -f "$SECRETS_FILE" ]]; then
  _saved_port="$(grep -E '^JUPYTER_PORT=' "$SECRETS_FILE" | cut -d= -f2- | tr -d \'\")"
  [[ -n "$_saved_port" ]] && JUPYTER_PORT="$_saved_port"
  _saved_port="$(grep -E '^MARIMO_PORT=' "$SECRETS_FILE" | cut -d= -f2- | tr -d \'\")"
  [[ -n "$_saved_port" ]] && MARIMO_PORT="$_saved_port"
  unset _saved_port
fi

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
    --cayleypy-source) CAYLEYPY_SOURCE="${2:?}"; shift 2 ;;
    --cayleypy-git) CAYLEYPY_GIT="${2:?}"; shift 2 ;;
    --cayleypy-pip) CAYLEYPY_PIP="${2:?}"; shift 2 ;;
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
    if [[ "$PUBLIC_MARIMO" == "ask" ]]; then
      PUBLIC_MARIMO="$(prompt_yes_no "Bind Marimo publicly with token auth" "yes")"
    fi
  fi
  CLOUDFLARE_TUNNEL="$(prompt_yes_no "Start/print Cloudflare quick tunnel" "$CLOUDFLARE_TUNNEL")"

  # Composable Checkbox menu for package groups!
  local options=(
    "core|$( [[ ",$PACKAGE_GROUPS," == *",core,"* ]] && echo yes || echo no )|JupyterLab, Jupyter Server, IPython kernel, packaging basics"
    "tpu|$( [[ ",$PACKAGE_GROUPS," == *",tpu,"* ]] && echo yes || echo no )|torch, torch_xla[tpu], numpy"
    "general-ds|$( [[ ",$PACKAGE_GROUPS," == *",general-ds,"* ]] && echo yes || echo no )|pandas, scipy, numba, polars, modin, daft, scikit-learn"
    "graphs|$( [[ ",$PACKAGE_GROUPS," == *",graphs,"* ]] && echo yes || echo no )|networkx, python-louvain, graphviz"
    "nlp|$( [[ ",$PACKAGE_GROUPS," == *",nlp,"* ]] && echo yes || echo no )|gensim, spacy"
    "llms|$( [[ ",$PACKAGE_GROUPS," == *",llms,"* ]] && echo yes || echo no )|transformers, accelerate, datasets, unsloth"
    "graphml|$( [[ ",$PACKAGE_GROUPS," == *",graphml,"* ]] && echo yes || echo no )|torch-geometric, pyg"
    "cayley-graphs|$( [[ ",$PACKAGE_GROUPS," == *",cayley-graphs,"* ]] && echo yes || echo no )|cayleypy (git or pypi)"
    "uis|$( [[ ",$PACKAGE_GROUPS," == *",uis,"* ]] && echo yes || echo no )|streamlit, plotly, dash, holoviz, panel, bokeh, holoviews, hvplot"
    "dev|$( [[ ",$PACKAGE_GROUPS," == *",dev,"* ]] && echo yes || echo no )|ruff, pytest, black, pre-commit"
  )
  PACKAGE_GROUPS="$(interactive_checkbox_menu "Select Python package groups to install:" "${options[@]}")"

  # Check each selected package group for optional packages
  local group selected_opts opt_pkg
  IFS=',' read -r -a selected_groups <<< "$PACKAGE_GROUPS"
  for group in "${selected_groups[@]}"; do
    local optional_pkgs=()
    while IFS= read -r opt_pkg; do
      [[ -n "$opt_pkg" ]] && optional_pkgs+=("$opt_pkg")
    done < <(get_optional_packages "$group")
    
    if (( ${#optional_pkgs[@]} > 0 )); then
      local opt_menu_options=()
      for opt_pkg in "${optional_pkgs[@]}"; do
        opt_menu_options+=("$opt_pkg|no|Optional package from $group group")
      done
      
      selected_opts="$(interactive_checkbox_menu "Select optional packages to install for group [$group]:" "${opt_menu_options[@]}")"
      if [[ -n "$selected_opts" ]]; then
        IFS=',' read -r -a opts_array <<< "$selected_opts"
        for opt_pkg in "${opts_array[@]}"; do
          EXTRA_INTERACTIVE_PACKAGES+=("$opt_pkg")
        done
      fi
    fi
  done
fi

[[ "$PUBLIC_JUPYTER" == "ask" ]] && PUBLIC_JUPYTER="yes"
# If Marimo is disabled, PUBLIC_MARIMO doesn't matter; if enabled and still
# "ask" (i.e. --yes / non-TTY path), default to same binding as Jupyter.
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
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && FIREWALL_SOURCE_RANGE="$ip/32" || FIREWALL_SOURCE_RANGE="<YOUR_IP_CIDR>"
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
    # Check if the existing venv's Python version matches what was requested.
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


group_packages() {
  local group="$1"
  local local_file="$SCRIPT_DIR/packages/$group.txt"
  local fallback_url="https://raw.githubusercontent.com/zakhar-kogan/tpu-dev-bootstrap/main/packages/$group.txt"
  
  if [[ -f "$local_file" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(echo -e "${line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      if [[ -n "$line" ]]; then
        eval echo "\"$line\""
      fi
    done < "$local_file"
  else
    # Try downloading it
    local content
    if content="$(curl -fsS --connect-timeout 2 --max-time 5 "$fallback_url" 2>/dev/null)"; then
      while IFS= read -r line; do
        line="${line%%#*}"
        line="$(echo -e "${line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [[ -n "$line" ]]; then
          eval echo "\"$line\""
        fi
      done <<< "$content"
    else
      # Offline / missing fallback list
      case "$group" in
        core)
          printf '%s\n' pip setuptools wheel ipykernel jupyterlab jupyter-server jupyterlab-git
          ;;
        tpu)
          printf '%s\n' numpy "torch==$TORCH_VERSION" "torch_xla[tpu]==$TORCH_XLA_VERSION"
          ;;
        general-ds)
          printf '%s\n' pandas scikit-learn numba scipy
          ;;
        graphs)
          printf '%s\n' networkx python-louvain graphviz
          ;;
        nlp)
          printf '%s\n' gensim spacy
          ;;
        llms)
          printf '%s\n' transformers accelerate datasets unsloth
          ;;
        graphml)
          printf '%s\n' torch-geometric pyg
          ;;
        cayley-graphs)
          printf '%s\n' cayleypy
          ;;
        uis)
          printf '%s\n' streamlit panel
          ;;
        dev)
          printf '%s\n' ruff pytest black pre-commit
          ;;
      esac
    fi
  fi
}

get_optional_packages() {
  local group="$1"
  local local_file="$SCRIPT_DIR/packages/$group.txt"
  local fallback_url="https://raw.githubusercontent.com/zakhar-kogan/tpu-dev-bootstrap/main/packages/$group.txt"
  
  local content=""
  if [[ -f "$local_file" ]]; then
    content="$(cat "$local_file")"
  else
    content="$(curl -fsS --connect-timeout 2 --max-time 5 "$fallback_url" 2>/dev/null || true)"
  fi
  
  local pattern='^[[:space:]]*#[[:space:]]*([^[:space:]]+)[[:space:]]*$'
  
  if [[ -n "$content" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ $pattern ]]; then
        local pkg="${BASH_REMATCH[1]}"
        eval echo "\"$pkg\""
      fi
    done <<< "$content"
  fi
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
  packages+=("${EXTRA_INTERACTIVE_PACKAGES[@]}")
  ((${#packages[@]} > 0)) || return 0
  run uv pip install --python "$VENV_DIR/bin/python" "${packages[@]}" -f https://storage.googleapis.com/libtpu-releases/index.html
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
    systemctl --user enable tpu-jupyter.service
    # Always restart so a re-run picks up changed flags (bind IP, port, token).
    # `restart` starts the service if not running, so `--now` is not needed.
    systemctl --user restart tpu-jupyter.service
    loginctl enable-linger "$USER" >/dev/null 2>&1 || true
  fi
}

install_marimo_service() {
  [[ "$ENABLE_MARIMO" == "yes" ]] || return 0
  # Use PUBLIC_MARIMO (not PUBLIC_JUPYTER) — they are independently configurable.
  local bind_ip="127.0.0.1"
  if [[ "$PUBLIC_MARIMO" == "yes" ]]; then
    bind_ip="0.0.0.0"
  fi
  log "Installing Marimo user service"
  local service
  service="[Unit]
Description=TPU Dev Marimo
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$ENV_DIR
Environment=PATH=$VENV_DIR/bin:$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$VENV_DIR/bin/marimo edit --host $bind_ip --port $MARIMO_PORT --headless --token --token-password=$MARIMO_TOKEN
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target"
  write_service "marimo" "$SYSTEMD_USER_DIR/tpu-marimo.service" "$service"
  if [[ "$DRY_RUN" != "yes" ]]; then
    systemctl --user daemon-reload
    systemctl --user enable tpu-marimo.service
    # Always restart so a re-run picks up changed flags (bind IP, port, token).
    systemctl --user restart tpu-marimo.service
  fi
}

install_tpu_workspace_tools() {
  log "Installing TPU workspace and status monitoring tools"
  run mkdir -p "$HOME/.local/bin"
  
  # 1. Write tpu-workspace
  if [[ "$DRY_RUN" != "yes" ]]; then
    cat <<'EOF' > "$HOME/.local/bin/tpu-workspace"
#!/usr/bin/env bash
set -Eeuo pipefail

SESSION_NAME="tpu-dev"

if ! command -v tmux &>/dev/null; then
  echo "tmux is not installed! Installing tmux..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y tmux
  else
    echo "Could not install tmux automatically. Please install it using your package manager."
    exit 1
  fi
fi

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "Attaching to existing tmux session: $SESSION_NAME"
  exec tmux attach-session -t "$SESSION_NAME"
fi

echo "Creating new tmux workspace session: $SESSION_NAME"
tmux new-session -d -s "$SESSION_NAME" -n "dev"

tmux new-window -t "$SESSION_NAME" -n "services"
if command -v btop &>/dev/null; then
  tmux send-keys -t "$SESSION_NAME:services.0" "btop" C-m
elif command -v htop &>/dev/null; then
  tmux send-keys -t "$SESSION_NAME:services.0" "htop" C-m
else
  tmux send-keys -t "$SESSION_NAME:services.0" "top" C-m
fi

tmux split-window -h -t "$SESSION_NAME:services"
tmux send-keys -t "$SESSION_NAME:services.1" "journalctl --user -u tpu-jupyter -f -n 100" C-m

if systemctl --user is-active tpu-marimo.service &>/dev/null; then
  tmux split-window -v -t "$SESSION_NAME:services.1"
  tmux send-keys -t "$SESSION_NAME:services.2" "journalctl --user -u tpu-marimo -f -n 100" C-m
fi

tmux select-window -t "$SESSION_NAME:dev"
exec tmux attach-session -t "$SESSION_NAME"
EOF
    chmod +x "$HOME/.local/bin/tpu-workspace"
  fi

  # 2. Write tpu-status
  if [[ "$DRY_RUN" != "yes" ]]; then
    cat <<'EOF' > "$HOME/.local/bin/tpu-status"
#!/usr/bin/env bash
set -Eeuo pipefail

BOLD="\033[1m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

printf "${CYAN}================================================================${RESET}\n"
printf "  ${BOLD}⚡ TPU-DEV SYSTEM & SERVICE STATUS ⚡${RESET}\n"
printf "${CYAN}================================================================${RESET}\n"

printf " ${BOLD}🖥️  System Metrics:${RESET}\n"
cpu_load=$(top -bn1 2>/dev/null | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
[[ -z "$cpu_load" ]] && cpu_load="N/A"
printf "   • CPU Load:  ${BOLD}%s%%${RESET}\n" "$cpu_load"

mem_total=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')
mem_used=$(free -m 2>/dev/null | awk '/Mem:/ {print $3}')
if [[ -n "$mem_total" && "$mem_total" -gt 0 ]]; then
  mem_pct=$(( mem_used * 100 / mem_total ))
  printf "   • Memory:    ${BOLD}%sMB / %sMB (%s%%)${RESET}\n" "$mem_used" "$mem_total" "$mem_pct"
else
  printf "   • Memory:    ${BOLD}N/A${RESET}\n"
fi

disk_pct=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}')
[[ -z "$disk_pct" ]] && disk_pct="N/A"
printf "   • Disk:      ${BOLD}%s used${RESET}\n" "$disk_pct"

printf "\n ${BOLD}🔌 Services:${RESET}\n"
if systemctl --user is-active tpu-jupyter.service &>/dev/null; then
  printf "   • Jupyter:   ${GREEN}Active${RESET}\n"
else
  printf "   • Jupyter:   ${RED}Inactive${RESET}\n"
fi

if systemctl --user is-active tpu-marimo.service &>/dev/null; then
  printf "   • Marimo:    ${GREEN}Active${RESET}\n"
else
  printf "   • Marimo:    ${RED}Inactive${RESET}\n"
fi

if [[ -f "$HOME/.config/tpu-dev/secrets.env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.config/tpu-dev/secrets.env"
  printf "   • Jupyter Port: ${BOLD}%s${RESET}\n" "${JUPYTER_PORT:-8888}"
  if [[ -n "${MARIMO_PORT:-}" ]]; then
    printf "   • Marimo Port:  ${BOLD}%s${RESET}\n" "$MARIMO_PORT"
  fi
fi

printf "\n ${BOLD}🐍 Active Python/ML Processes:${RESET}\n"
pids=$(pgrep -f "python" || true)
if [[ -n "$pids" ]]; then
  ps -o pid,ppid,cmd -p $pids 2>/dev/null | grep -v grep | head -n 15 | while read -r line; do
    printf "   • %s\n" "$line"
  done
else
  printf "   • No active Python processes found.\n"
fi

printf "\n ${BOLD}💡 Shortcuts:${RESET}\n"
printf "   • Open tmux workspace:   ${BOLD}tpu-workspace${RESET}\n"
printf "   • View Jupyter status:   ${BOLD}systemctl --user status tpu-jupyter${RESET}\n"
printf "   • View Jupyter logs:     ${BOLD}journalctl --user -u tpu-jupyter -f -n 50${RESET}\n"
printf "${CYAN}================================================================${RESET}\n"
EOF
    chmod +x "$HOME/.local/bin/tpu-status"
  fi

  # 3. Add Welcome banner to .bashrc
  if [[ "$DRY_RUN" != "yes" ]]; then
    local entry_check="tpu-status"
    if ! grep -q "$entry_check" "$HOME/.bashrc" 2>/dev/null; then
      {
        printf '\n# TPU development environment welcome message\n'
        printf 'if [[ -t 0 && -t 1 ]]; then\n'
        printf '  echo -e "\\n\\033[1;36m⚡ Welcome to your TPU Development Environment! ⚡\\033[0m"\n'
        printf '  echo -e "   • Run \\033[1mcustom package lists\\033[0m: modify ~/.local/share/tpu-dev/envs/tpu-dev (or similar)\\n"\n'
        printf '  echo -e "   • Run \\033[1mtpu-status\\033[0m to view active services and metrics."\n'
        printf '  echo -e "   • Run \\033[1mtpu-workspace\\033[0m to enter your tmux log and shell panel.\\n"\n'
        printf 'fi\n'
      } >> "$HOME/.bashrc"
    fi
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
  local marimo_rule_name="allow-tpu-marimo-$MARIMO_PORT"
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
    if ! command -v gcloud >/dev/null 2>&1; then
      warn "gcloud is not available here; printing firewall commands to run from your local machine or Cloud Shell."
    else
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
  fi
  cat <<EOF

🔥 Firewall commands
Source ranges are the client IPs allowed to connect. Current source range:

  $FIREWALL_SOURCE_RANGE

Run these from your laptop or Cloud Shell, not from the TPU VM.

JupyterLab firewall:

  if gcloud compute firewall-rules describe $rule_name${GCP_PROJECT:+ --project $GCP_PROJECT} >/dev/null 2>&1; then
    gcloud compute firewall-rules update $rule_name \\
      --allow tcp:$JUPYTER_PORT \\
      --source-ranges $FIREWALL_SOURCE_RANGE${GCP_PROJECT:+ \\
      --project $GCP_PROJECT}
  else
    gcloud compute firewall-rules create $rule_name \\
      --allow tcp:$JUPYTER_PORT \\
      --network default \\
      --source-ranges $FIREWALL_SOURCE_RANGE${GCP_PROJECT:+ \\
      --project $GCP_PROJECT}
  fi
EOF

  if [[ "$ENABLE_MARIMO" == "yes" ]]; then
    cat <<EOF

Marimo firewall:

  if gcloud compute firewall-rules describe $marimo_rule_name${GCP_PROJECT:+ --project $GCP_PROJECT} >/dev/null 2>&1; then
    gcloud compute firewall-rules update $marimo_rule_name \\
      --allow tcp:$MARIMO_PORT \\
      --source-ranges $FIREWALL_SOURCE_RANGE${GCP_PROJECT:+ \\
      --project $GCP_PROJECT}
  else
    gcloud compute firewall-rules create $marimo_rule_name \\
      --allow tcp:$MARIMO_PORT \\
      --network default \\
      --source-ranges $FIREWALL_SOURCE_RANGE${GCP_PROJECT:+ \\
      --project $GCP_PROJECT}
  fi
EOF
  fi

  cat <<EOF

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
  local rule_name="allow-tpu-ssh-$SSH_PORT"
  local command=(
    gcloud compute firewall-rules create "$rule_name"
    --allow "tcp:$SSH_PORT"
    --network default
    --source-ranges "$ssh_source_range"
  )
  if [[ -n "$GCP_PROJECT" ]]; then
    command+=(--project "$GCP_PROJECT")
  fi
  if [[ "$APPLY_SSH_FIREWALL" == "yes" ]]; then
    if ! command -v gcloud >/dev/null 2>&1; then
      warn "gcloud is not available here; printing SSH firewall command to run from your local machine or Cloud Shell."
    else
      log "Creating SSH firewall rule $rule_name"
      if gcloud compute firewall-rules describe "$rule_name" ${GCP_PROJECT:+--project "$GCP_PROJECT"} >/dev/null 2>&1; then
        run gcloud compute firewall-rules update "$rule_name" \
          --allow "tcp:$SSH_PORT" \
          --source-ranges "$ssh_source_range" \
          ${GCP_PROJECT:+--project "$GCP_PROJECT"}
      else
        run "${command[@]}"
      fi
    fi
  fi
  cat <<EOF

🔑 SSH firewall
Direct SSH needs tcp:$SSH_PORT open unless an existing firewall rule already covers it.

  if gcloud compute firewall-rules describe $rule_name${GCP_PROJECT:+ --project $GCP_PROJECT} >/dev/null 2>&1; then
    gcloud compute firewall-rules update $rule_name \\
      --allow tcp:$SSH_PORT \\
      --source-ranges $ssh_source_range${GCP_PROJECT:+ \\
      --project $GCP_PROJECT}
  else
    gcloud compute firewall-rules create $rule_name \\
      --allow tcp:$SSH_PORT \\
      --network default \\
      --source-ranges $ssh_source_range${GCP_PROJECT:+ \\
      --project $GCP_PROJECT}
  fi
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
  if [[ "$DRY_RUN" != "yes" && -f "$SHARE_SSH_KEY_PATH.pub" ]]; then
    # Resolve the target user's home directory. When --share-ssh-user differs
    # from $USER (e.g. "ubuntu") the key must go into *their* authorized_keys,
    # not the installer user's.
    local target_home
    target_home="$(getent passwd "$SHARE_SSH_USER" 2>/dev/null | cut -d: -f6 || true)"
    if [[ -z "$target_home" ]]; then
      warn "Could not resolve home for user '$SHARE_SSH_USER'; falling back to $HOME"
      target_home="$HOME"
    fi
    local target_auth="$target_home/.ssh/authorized_keys"
    log "Adding shareable SSH public key to $target_auth"
    if [[ "$SHARE_SSH_USER" != "$USER" ]]; then
      # Need elevated permissions to write to another user's .ssh directory.
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
  # Only generates the worker helper script; display is handled by print_summary.
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


SEP="────────────────────────────────────────────────────────"

print_marimo_summary() { :; }  # merged into print_summary

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

  # ── SSH ────────────────────────────────────────────────────────
  printf '\n%s\n' "$SEP"
  printf '🔑  SSH\n\n'
  printf '  gcloud:  gcloud compute tpus tpu-vm ssh %s %s --zone=%s\n' \
    "$ssh_target" "$project_flag" "$ssh_zone"
  # Show key info if key was just generated OR if one already exists on disk.
  local ssh_host="${TPU_EXTERNAL_IP:-<TPU_EXTERNAL_IP>}"
  if [[ -f "$SHARE_SSH_KEY_PATH" ]]; then
    printf '  direct:  ssh -i %s -o IdentitiesOnly=yes -p %s %s@%s\n' \
      "$SHARE_SSH_KEY_PATH" "$SSH_PORT" "$SHARE_SSH_USER" "$ssh_host"
    printf '  key:     cat %s\n' "$SHARE_SSH_KEY_PATH"
    local command_file="$SHARE_SSH_KEY_PATH.add-to-tpu.sh"
    [[ -f "$command_file" ]] && printf '  workers: %s\n' "$command_file"
  fi

  # ── JupyterLab ─────────────────────────────────────────────────
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

  # ── Marimo ─────────────────────────────────────────────────────
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

  # ── Workspace & Monitoring ─────────────────────────────────────
  printf '\n%s\n' "$SEP"
  printf '⚡  Workspace & Monitoring\n\n'
  printf '  status:    tpu-status     (view live CPU, memory, and active processes)\n'
  printf '  workspace: tpu-workspace  (starts/attaches tmux panel with dev shell and service logs)\n'

  printf '\n%s\n\n' "$SEP"
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
  install_tpu_workspace_tools
  generate_share_ssh_key
  print_firewall_commands
  print_ssh_firewall_commands
  print_cloudflare
  print_share_ssh_instructions
  print_marimo_summary
  print_summary
}

main "$@"

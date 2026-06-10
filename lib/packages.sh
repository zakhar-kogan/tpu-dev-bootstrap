#!/usr/bin/env bash
# lib/packages.sh — Package group loading and installation.

# Read packages from a group .txt file, expanding only known variables.
# Falls back to a hardcoded minimal list if the file is missing and
# the network fallback also fails.
group_packages() {
  local group="$1"
  local local_file="$SCRIPT_DIR/packages/$group.txt"

  if [[ -f "$local_file" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"                     # strip comments
      line="${line#"${line%%[![:space:]]*}"}" # trim leading whitespace
      line="${line%"${line##*[![:space:]]}"}" # trim trailing whitespace
      if [[ -n "$line" ]]; then
        # Safe variable expansion for known vars only (no eval).
        line="${line//\$TORCH_VERSION/$TORCH_VERSION}"
        line="${line//\$TORCH_XLA_VERSION/$TORCH_XLA_VERSION}"
        printf '%s\n' "$line"
      fi
    done < "$local_file"
  else
    # Offline / file not found — hardcoded fallback for essential groups.
    case "$group" in
      core)
        printf '%s\n' pip setuptools wheel ipykernel jupyterlab jupyter-server jupyterlab-git
        ;;
      tpu)
        printf '%s\n' numpy "torch==$TORCH_VERSION" "torch_xla[tpu]==$TORCH_XLA_VERSION" "jax[tpu]"
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
  packages+=("${EXTRA_PIP[@]}")
  ((${#packages[@]} > 0)) || return 0
  run uv pip install --python "$VENV_DIR/bin/python" "${packages[@]}" -f https://storage.googleapis.com/libtpu-releases/index.html -f https://storage.googleapis.com/jax-releases/libtpu_releases.html
}

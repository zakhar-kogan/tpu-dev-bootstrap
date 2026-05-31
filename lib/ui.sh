#!/usr/bin/env bash
# lib/ui.sh — Logging, prompts, parse helpers, and interactive UI.

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

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

# Run a command, or print it in dry-run mode.
run() {
  if [[ "$DRY_RUN" == "yes" ]]; then
    printf 'DRY-RUN: %q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# Display a numbered list of package groups with current selection markers.
# Reads PACKAGE_GROUPS (comma-separated) and prompts the user to toggle.
# Usage: select_groups
select_groups() {
  local all_groups=(core tpu general-ds graphs nlp cayley-graphs llms graphml uis dev)
  local descriptions=(
    "JupyterLab, Jupyter Server, IPython kernel, packaging basics"
    "torch, torch_xla[tpu], numpy"
    "pandas, scikit-learn, numba, scipy"
    "networkx, python-louvain, graphviz"
    "gensim, spacy"
    "cayleypy"
    "transformers, accelerate, datasets, unsloth"
    "torch-geometric, pyg"
    "streamlit, panel"
    "ruff, pytest, black, pre-commit"
  )

  printf '\n'
  local i
  for i in "${!all_groups[@]}"; do
    local g="${all_groups[i]}"
    local marker=" "
    [[ ",$PACKAGE_GROUPS," == *",$g,"* ]] && marker="*"
    printf '  %s %2d) %-16s — %s\n' "$marker" "$((i + 1))" "$g" "${descriptions[i]}"
  done
  printf '\n  (* = currently selected)\n\n'

  local input
  read -rp "  Toggle groups (comma-separated numbers, Enter to keep): " input < /dev/tty || input=""
  [[ -z "$input" ]] && return

  # Parse the numbers and toggle each group
  IFS=',' read -r -a toggles <<< "$input"
  for num in "${toggles[@]}"; do
    num="${num// /}"  # strip spaces
    if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#all_groups[@]} )); then
      local g="${all_groups[num - 1]}"
      if [[ ",$PACKAGE_GROUPS," == *",$g,"* ]]; then
        # Remove the group
        PACKAGE_GROUPS="$(echo "$PACKAGE_GROUPS" | sed "s/,$g,/,/; s/^$g,//; s/,$g$//; s/^$g$//")"
      else
        # Add the group
        [[ -n "$PACKAGE_GROUPS" ]] && PACKAGE_GROUPS="$PACKAGE_GROUPS,$g" || PACKAGE_GROUPS="$g"
      fi
    fi
  done
}

#!/usr/bin/env bash
# TPU development environment welcome banner.
# Sourced from .bashrc — do not set -e or pipefail here.

if [[ -t 0 && -t 1 ]]; then
  echo -e "\n\033[1;36m⚡ Welcome to your TPU Development Environment! ⚡\033[0m"
  echo -e "   • Run \033[1mtpu-status\033[0m to view active services and metrics."
  echo -e "   • Run \033[1mtpu-workspace\033[0m to enter your tmux log and shell panel.\n"
fi

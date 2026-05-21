#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${IMAGE:-tpu-dev-bootstrap:latest}"
PORT="${PORT:-8888}"

docker run --rm -it \
  --privileged \
  --net=host \
  -v "$PWD:/workspace" \
  "$IMAGE" \
  jupyter lab --ip=0.0.0.0 --port="$PORT" --no-browser

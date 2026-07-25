#!/bin/bash
set -euo pipefail

# Resolve the repo root from this script's own location so it works from any
# working directory — compose needs to run where compose.yaml and .env live.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
cd "$repo_root"

if ! docker info >/dev/null 2>&1; then
  echo "docker daemon is not running" >&2
  exit 1
fi

docker compose up --build --detach --remove-orphans --wait --wait-timeout 60 "$@"

echo
docker compose ps
echo
echo "logs:  docker compose logs -f"
echo "stop:  ./scripts/down.sh"

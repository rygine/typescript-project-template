#!/bin/bash
set -euo pipefail

# Resolve the repo root from this script's own location so it works from any
# working directory — compose needs to run where compose.yaml and .env live.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
cd "$repo_root"

# Volumes are kept on purpose: `down -v` deletes the named volume backing
# $DATA_DIR and everything the service wrote there. Pass -v yourself when you
# mean it — `./scripts/down.sh -v`.
docker compose down --remove-orphans "$@"

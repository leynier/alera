#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || (${2:-} != "" && ${2:-} != "--dry-run") ]]; then
  echo "usage: deploy_worker_relay_disabled.sh <edge-directory> [--dry-run]" >&2
  exit 2
fi

edge_directory="$(cd "$1" && pwd)"
deploy_arguments=()
if [[ ${2:-} == "--dry-run" ]]; then
  deploy_arguments+=(--dry-run)
fi
recovery_config="$(mktemp "$edge_directory/.wrangler-relay-disabled.XXXXXX.jsonc")"
trap 'rm -f "$recovery_config"' EXIT

jq '.vars = (.vars // {}) | .vars.RELAY_ENABLED = "false"' \
  "$edge_directory/wrangler.jsonc" >"$recovery_config"

(
  cd "$edge_directory"
  bunx wrangler deploy --config "$recovery_config" "${deploy_arguments[@]}"
)

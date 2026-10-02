#!/usr/bin/env bash

set -euo pipefail

channel="${1:-}"
if [[ "$channel" != "stable" ]]; then
  echo "::notice::Skipping the production landing deployment hook for the $channel release channel."
  exit 0
fi

if [[ -z "${VERCEL_PRODUCTION_DEPLOY_HOOK:-}" ]]; then
  echo "::error::VERCEL_PRODUCTION_DEPLOY_HOOK is required for stable release publication." >&2
  exit 1
fi

temporary_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
response_file="$temporary_root/alera-vercel-deploy-hook-response"
config_file="$temporary_root/alera-vercel-deploy-hook-config"
trap 'rm -f "$response_file" "$config_file"' EXIT

# Keep the credential out of curl's argv, which is visible to other processes
# on the runner. The temporary config is mode 0600 and is removed on exit.
(umask 077 && printf 'url = "%s"\n' "$VERCEL_PRODUCTION_DEPLOY_HOOK" >"$config_file")

if ! http_status="$(curl \
  --silent \
  --show-error \
  --location \
  --max-time 30 \
  --retry 2 \
  --retry-delay 2 \
  --output "$response_file" \
  --write-out '%{http_code}' \
  --config "$config_file")"; then
  echo "::error::The Vercel production landing deployment hook request failed after stable release publication." >&2
  exit 1
fi

if [[ "$http_status" != 2?? ]]; then
  echo "::error::The Vercel production landing deployment hook returned HTTP $http_status after stable release publication." >&2
  exit 1
fi

echo "::notice::Vercel accepted the stable landing deployment request."

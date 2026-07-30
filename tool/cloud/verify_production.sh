#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: verify_production.sh <public-url> <origin-url>" >&2
  exit 2
fi

public_url="${1%/}"
origin_url="${2%/}"
attempts=12

retry_curl() {
  local url="$1"
  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent --show-error --max-time 20 "$url" >/dev/null; then
      return 0
    fi
    sleep 5
  done
  return 1
}

retry_curl "$public_url/health"
retry_curl "$public_url/.well-known/jwks.json"

origin_status="$(
  curl \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out '%{http_code}' \
    --max-time 20 \
    "$origin_url/.well-known/jwks.json"
)"
if [[ "$origin_status" != "401" ]]; then
  echo "direct origin JWKS returned $origin_status; expected 401" >&2
  exit 1
fi

echo "public health and JWKS succeeded; direct origin JWKS remained closed"

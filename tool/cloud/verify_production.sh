#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: verify_production.sh <public-url> <origin-url> <relay-state>" >&2
  exit 2
fi

public_url="${1%/}"
origin_url="${2%/}"
relay_state="$3"
attempts=12

case "$relay_state" in
  disabled)
    expected_relay_status=404
    ;;
  enabled)
    expected_relay_status=426
    ;;
  *)
    echo "relay-state must be disabled or enabled" >&2
    exit 2
    ;;
esac

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

relay_status=""
for ((attempt = 1; attempt <= attempts; attempt++)); do
  if relay_status="$(
    curl \
      --silent \
      --show-error \
      --output /dev/null \
      --write-out '%{http_code}' \
      --max-time 20 \
      "$public_url/v1/relay/deploy-probe"
  )" && [[ "$relay_status" == "$expected_relay_status" ]]; then
    break
  fi
  sleep 5
done
if [[ "$relay_status" != "$expected_relay_status" ]]; then
  echo "public relay probe returned $relay_status; expected $expected_relay_status for $relay_state" >&2
  exit 1
fi

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

echo "public health and JWKS succeeded; relay was $relay_state; direct origin JWKS remained closed"

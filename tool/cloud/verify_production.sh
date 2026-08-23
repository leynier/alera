#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "usage: verify_production.sh <public-url> <origin-url> <relay-state> [relay-control-state]" >&2
  exit 2
fi

public_url="${1%/}"
origin_url="${2%/}"
relay_state="$3"
relay_control_state="${4:-backend}"
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

case "$relay_control_state" in
  backend)
    expected_relay_control_status=401
    ;;
  worker)
    expected_relay_control_status=426
    ;;
  *)
    echo "relay-control-state must be backend or worker" >&2
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

for relay_control_probe in \
  '/v1/relay/identity|{"publicKey":"deploy-probe","keyVersion":1}' \
  '/v1/relay/grants|{"runtimeId":"deploy-probe"}'; do
  relay_control_path="${relay_control_probe%%|*}"
  relay_control_body="${relay_control_probe#*|}"
  relay_control_status=""
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if relay_control_status="$(
      curl \
        --silent \
        --show-error \
        --output /dev/null \
        --write-out '%{http_code}' \
        --max-time 20 \
        --header 'content-type: application/json' \
        --data "$relay_control_body" \
        "$public_url$relay_control_path"
    )" && [[ "$relay_control_status" == "$expected_relay_control_status" ]]; then
      break
    fi
    sleep 5
  done
  if [[ "$relay_control_status" != "$expected_relay_control_status" ]]; then
    echo "public relay control path $relay_control_path returned $relay_control_status; expected $expected_relay_control_status for $relay_control_state" >&2
    exit 1
  fi
done

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

echo "public health and JWKS succeeded; relay was $relay_state; relay control state was $relay_control_state; direct origin JWKS remained closed"

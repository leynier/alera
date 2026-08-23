#!/usr/bin/env bash
set -euo pipefail

public_url=https://public.test
origin_url=https://origin.test

curl() {
  local data=""
  local url=""
  while (($# > 0)); do
    case "$1" in
      --data)
        data="$2"
        shift 2
        continue
        ;;
      http*)
        url="$1"
        ;;
    esac
    shift
  done

  case "$url" in
    "$public_url/health"|"$public_url/.well-known/jwks.json")
      ;;
    "$public_url/v1/relay/deploy-probe")
      printf '%s' "$TEST_RELAY_STATUS"
      ;;
    "$public_url/v1/relay/identity")
      [[ "$data" == '{"publicKey":"deploy-probe","keyVersion":1}' ]]
      printf '%s' "$TEST_RELAY_CONTROL_STATUS"
      ;;
    "$public_url/v1/relay/grants")
      [[ "$data" == '{"runtimeId":"deploy-probe"}' ]]
      printf '%s' "$TEST_RELAY_CONTROL_STATUS"
      ;;
    "$origin_url/.well-known/jwks.json")
      printf '401'
      ;;
    *)
      echo "unexpected verifier URL: $url" >&2
      return 1
      ;;
  esac
}
export -f curl

TEST_RELAY_STATUS=404 TEST_RELAY_CONTROL_STATUS=401 \
  tool/cloud/verify_production.sh "$public_url" "$origin_url" disabled backend
TEST_RELAY_STATUS=426 TEST_RELAY_CONTROL_STATUS=401 \
  tool/cloud/verify_production.sh "$public_url" "$origin_url" enabled backend
TEST_RELAY_STATUS=426 TEST_RELAY_CONTROL_STATUS=426 \
  tool/cloud/verify_production.sh "$public_url" "$origin_url" enabled worker

set +e
tool/cloud/verify_production.sh "$public_url" "$origin_url" enabled invalid >/dev/null 2>&1
invalid_status=$?
set -e
if [[ "$invalid_status" -ne 2 ]]; then
  echo "invalid relay control state returned $invalid_status; expected 2" >&2
  exit 1
fi

echo "verify_production tests passed"

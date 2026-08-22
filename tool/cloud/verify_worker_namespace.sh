#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: verify_worker_namespace.sh <account-id> <worker-name> <class-name>" >&2
  exit 2
fi

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "CLOUDFLARE_API_TOKEN is required" >&2
  exit 2
fi

account_id="$1"
worker_name="$2"
class_name="$3"

namespace=""
for attempt in {1..12}; do
  if response="$(
    curl \
      --fail-with-body \
      --silent \
      --show-error \
      --max-time 30 \
      --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$account_id/workers/durable_objects/namespaces?per_page=1000"
  )" && namespace="$(
    jq -cer \
      --arg worker "$worker_name" \
      --arg class "$class_name" \
      '
        select(.success == true)
        | .result
        | map(select(.class == $class))
        | if length != 1 then
            error("expected exactly one namespace for " + $class)
          else
            .[0]
          end
        | select(.script == $worker)
        | select(.use_sqlite == true)
      ' <<<"$response" 2>/dev/null
  )"; then
    break
  fi
  namespace=""
  sleep 5
done

if [[ -z "$namespace" ]]; then
  echo "expected one SQLite namespace for $worker_name/$class_name" >&2
  exit 1
fi

namespace_id="$(jq -r '.id' <<<"$namespace")"
echo "verified SQLite Durable Object namespace $namespace_id for $worker_name/$class_name"

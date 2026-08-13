#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -lt 3 ]]; then
  echo "Usage: $0 <tag> <repository> <asset>..." >&2
  exit 64
fi

tag="$1"
repository="$2"
shift 2

asset_names=()
for asset in "$@"; do
  if [[ ! -s "$asset" ]]; then
    echo "::error::Missing or empty release asset: $asset" >&2
    exit 1
  fi
  asset_name="${asset##*/}"
  asset_names+=("$asset_name")
done
for ((index = 0; index < ${#asset_names[@]}; index++)); do
  for ((previous = 0; previous < index; previous++)); do
    if [[ "${asset_names[$index]}" == "${asset_names[$previous]}" ]]; then
      echo "::error::Duplicate release asset name: ${asset_names[$index]}" >&2
      exit 64
    fi
  done
done

readonly max_attempts=3
for asset in "$@"; do
  asset_name="${asset##*/}"
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    # One asset per invocation prevents gh's five concurrent upload workers
    # from masking which upload failed. On a retry, --clobber removes an asset
    # that GitHub accepted before returning a transient server error.
    if gh release upload "$tag" "$asset" \
      --repo "$repository" \
      --clobber; then
      break
    fi
    if ((attempt == max_attempts)); then
      echo "::error::Failed to upload $asset_name after $max_attempts attempts." >&2
      exit 1
    fi
    echo "::warning::Upload of $asset_name failed on attempt $attempt; retrying."
    sleep "$((attempt * 2))"
  done
done

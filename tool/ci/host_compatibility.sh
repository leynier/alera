#!/usr/bin/env bash
set -euo pipefail

# v0.49.0 is the latest stable release before agentProfileOrderingV1. It still
# speaks protocol 4 and supports the profile catalog and terminal launch flow.
readonly previous_tag="v0.49.0"
readonly previous_version="0.49.0"
readonly previous_commit="e60c96ec7522052e9af81ab15ae5d6da2443dac4"
readonly root="$(git rev-parse --show-toplevel)"
readonly stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

# Fetch only the tagged history tip into a disposable repository. This neither
# deepens the checkout nor updates a contributor's local tag.
readonly origin="$(git remote get-url origin)"
readonly release_repo="$stage/release-repo"
git init --quiet "$release_repo"
git -C "$release_repo" fetch --quiet --depth=1 --no-tags \
  "$origin" "refs/tags/$previous_tag"
resolved_commit="$(git -C "$release_repo" rev-parse 'FETCH_HEAD^{commit}')"
if [[ "$resolved_commit" != "$previous_commit" ]]; then
  echo "$previous_tag resolved to $resolved_commit, expected $previous_commit" >&2
  exit 1
fi

mkdir -p "$stage/source" "$stage/bin"
git -C "$release_repo" archive "$resolved_commit" | tar -x -C "$stage/source"

(
  cd "$stage/source/rust"
  ALERA_BUILD_VERSION="$previous_version" \
  ALERA_BUILD_COMMIT="$previous_commit" \
  CARGO_TARGET_DIR="$stage/target" \
    cargo build --locked -p alera-cli
)
cp "$stage/target/debug/alera" "$stage/bin/alera"

(
  cd "$root/rust"
  ALERA_PREVIOUS_HOST_BINARY="$stage/bin/alera" \
  ALERA_PREVIOUS_HOST_VERSION="$previous_version" \
    cargo test \
      --locked \
      -p alera-cli \
      --test host_version_compatibility \
      v049_host_accepts_current_baseline_client \
      -- --exact --ignored
)

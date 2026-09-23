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

_host_platform() {
  case "$(uname -s)" in
    Linux) echo linux ;;
    Darwin) echo macos ;;
    *)
      echo "host compatibility has no published runtime for $(uname -s)" >&2
      return 1
      ;;
  esac
}

_host_arch() {
  case "$(uname -m)" in
    x86_64) echo x64 ;;
    aarch64|arm64) echo arm64 ;;
    *)
      echo "host compatibility has no published runtime for $(uname -m)" >&2
      return 1
      ;;
  esac
}

_pinned_sha256() {
  case "$1" in
    alera-runtime-0.49.0-linux-x64.tar.gz)
      echo d0f29c75c2163e3764d7fbf2bb4e605007f2447a890e5bf1190f359516d86d13
      ;;
    alera-runtime-0.49.0-linux-arm64.tar.gz)
      echo bc0f3bc723151788927cd3158f737e649e780806ff8f6c421806f40ecb9f9114
      ;;
    alera-runtime-0.49.0-macos-arm64.tar.gz)
      echo 51070d81452fc943e458ed713ca9dd5347bb4509377352a39625b400ada1dd9b
      ;;
    alera-runtime-0.49.0-macos-x64.tar.gz)
      echo ef08ff4aa5a857e38ae78d1aab629e89ab90172ae5c0a14355fb67f5d7668eaf
      ;;
    *)
      echo "No pinned SHA-256 for $1" >&2
      return 1
      ;;
  esac
}

_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Fetch only the tagged history tip into a disposable repository. This neither
# deepens the checkout nor updates a contributor's local tag. Moving the tag
# off this commit must fail the job even when the published tarball is reused.
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

# The published runtime tarball is the host users actually ran. Rebuilding it
# from source in CI added ~5.5 minutes on the PR Checks critical path after
# `cargo test` had already compiled the current workspace. That artifact
# reports crate version 0.1.0 and commit 17a183f51debfc29114c0e682bc917ed4cdc58ae
# (parent of this tag). Product 0.49.0 is the tag plus this tarball.
host_platform="${ALERA_PREVIOUS_HOST_PLATFORM:-$(_host_platform)}"
host_arch="${ALERA_PREVIOUS_HOST_ARCH:-$(_host_arch)}"
readonly asset_name="alera-runtime-${previous_version}-${host_platform}-${host_arch}.tar.gz"
expected_sha256="${ALERA_PREVIOUS_HOST_SHA256:-$(_pinned_sha256 "$asset_name")}"
readonly asset_url="https://github.com/leynier/alera/releases/download/${previous_tag}/${asset_name}"
readonly asset_path="$stage/$asset_name"

curl --fail --location --retry 5 --retry-all-errors \
  --output "$asset_path" "$asset_url"
actual_sha256="$(_sha256 "$asset_path")"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "$asset_name hash mismatch: expected $expected_sha256, got $actual_sha256" >&2
  exit 1
fi

mkdir -p "$stage/bin"
tar -xzf "$asset_path" -C "$stage/bin"
readonly previous_binary="$stage/bin/alera"
if [[ ! -x "$previous_binary" ]]; then
  chmod +x "$previous_binary"
fi
if [[ ! -x "$previous_binary" ]]; then
  echo "Published runtime tarball did not contain an executable alera binary." >&2
  exit 1
fi

manifest_path="$stage/bin/runtime-manifest.json"
if [[ ! -f "$manifest_path" ]]; then
  echo "Published runtime tarball did not contain runtime-manifest.json." >&2
  exit 1
fi
manifest_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$manifest_path")"
if [[ "$manifest_version" != "$previous_version" ]]; then
  echo "runtime-manifest.json version was $manifest_version, expected $previous_version" >&2
  exit 1
fi

(
  cd "$root/rust"
  # `--workspace` keeps the same feature unification as
  # run_rust_workspace_tests.sh so this ignored test does not relink.
  ALERA_PREVIOUS_HOST_BINARY="$previous_binary" \
  ALERA_PREVIOUS_HOST_VERSION="$previous_version" \
    cargo test \
      --workspace \
      --locked \
      --test host_version_compatibility \
      v049_host_accepts_current_baseline_client \
      -- --exact --ignored
)

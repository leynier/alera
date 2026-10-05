#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -gt 1 ]]; then
  echo "Usage: $0 [cargo-executable]" >&2
  exit 64
fi
cargo_bin="${1:-cargo}"
root="$(git rev-parse --show-toplevel)"
cd "$root/rust"
export ALERA_BUILD_COMMIT=unknown
unset ALERA_BUILD_VERSION

"$cargo_bin" fmt --check
"$cargo_bin" clippy --workspace --all-targets -- -D warnings
"$cargo_bin" test --workspace

#!/usr/bin/env bash
set -euo pipefail

# Compiles the workspace once, then runs tests with the PTY-heavy
# orchestration_review_regressions binary isolated. That binary drives real
# PTYs and flakes when cargo runs it in parallel with other integration
# binaries (see AGENTS.md). Serializing only that binary keeps the rest of
# the suite parallel.
root="$(git rev-parse --show-toplevel)"
cd "$root/rust"

cargo test --workspace --locked --no-run
cargo test --workspace --locked --exclude alera-cli
# alera-cli is a bin-only package; --lib would fail.
cargo test --locked -p alera-cli --bins

other_integration_tests=()
for file in alera-cli/tests/*.rs; do
  name="$(basename "$file" .rs)"
  if [[ "$name" == "orchestration_review_regressions" ]]; then
    continue
  fi
  other_integration_tests+=(--test "$name")
done
if ((${#other_integration_tests[@]} > 0)); then
  cargo test --locked -p alera-cli "${other_integration_tests[@]}"
fi

cargo test --locked -p alera-cli --test orchestration_review_regressions -- --test-threads=1

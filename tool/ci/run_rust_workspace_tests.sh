#!/usr/bin/env bash
set -euo pipefail

# Compiles the workspace once under the full feature set, then runs
# orchestration_review_regressions alone. That binary drives real PTYs and
# flakes when cargo runs it in parallel with other integration binaries (see
# AGENTS.md). Serializing only that binary keeps the rest of the suite
# parallel.
#
# Every cargo test invocation MUST keep `--workspace`. Dropping alera-cli
# from the package set (`--exclude` or a later `-p alera-cli`) changes
# feature unification and relinks shared crates. On PR Checks run
# 34191563476 that added ~3m 15s plus ~2m 36s after a 3m 30s `--no-run`.
root="$(git rev-parse --show-toplevel)"
cd "$root/rust"

other_integration_tests=()
for file in alera-cli/tests/*.rs; do
  name="$(basename "$file" .rs)"
  if [[ "$name" == "orchestration_review_regressions" ]]; then
    continue
  fi
  other_integration_tests+=(--test "$name")
done

# `--doc` cannot mix with other target selectors. This workspace has no
# rustdoc tests, so omitting `--doc` drops nothing.
cargo test --workspace --locked --lib --bins \
  "${other_integration_tests[@]}"

cargo test --workspace --locked --test orchestration_review_regressions \
  -- --test-threads=1

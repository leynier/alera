#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

fail() {
  echo "$*" >&2
  exit 1
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "Missing expected output: $2"
}

assert_not_contains() {
  [[ "$1" != *"$2"* ]] || fail "Unexpected output: $2"
}

# Compile the actual build script without the workspace's native dependencies.
(
  cd "$root/rust"
  rustc --edition=2021 alera-cli/build.rs -o "$stage/build-script.exe"
)
git init --quiet "$stage/repo"
commit_fixture() {
  git -C "$stage/repo" \
    -c core.hooksPath="$stage/no-hooks" -c commit.gpgsign=false \
    -c user.name=CacheTest -c user.email=cache-test@example.invalid \
    commit --quiet --allow-empty -m "$1"
}
commit_fixture first
first_commit="$(git -C "$stage/repo" rev-parse HEAD)"

build_metadata() {
  (
    cd "$stage/repo"
    env -u ALERA_BUILD_COMMIT -u ALERA_BUILD_VERSION \
      CARGO_MANIFEST_DIR="$stage/repo" \
      CARGO_PKG_VERSION=0.1.0 \
      CARGO_CFG_TARGET_OS=linux CARGO_CFG_TARGET_ENV=gnu \
      "$@" "$stage/build-script.exe"
  )
}

default_metadata="$(build_metadata)"
assert_contains "$default_metadata" "cargo:rustc-env=ALERA_BUILD_COMMIT=$first_commit"
assert_contains "$default_metadata" 'cargo:rerun-if-changed='
stable_metadata="$(build_metadata ALERA_BUILD_COMMIT=unknown)"
assert_not_contains "$stable_metadata" 'cargo:rerun-if-changed='
assert_contains "$stable_metadata" 'cargo:rustc-env=ALERA_BUILD_COMMIT=unknown'
[[ "$(build_metadata ALERA_BUILD_COMMIT=unknown ALERA_BUILD_VERSION=)" == "$stable_metadata" ]] || \
  fail 'An empty check version changed build metadata'
assert_contains "$stable_metadata" 'cargo:rustc-env=ALERA_BUILD_VERSION=0.1.0'

commit_fixture second
second_commit="$(git -C "$stage/repo" rev-parse HEAD)"
[[ "$first_commit" != "$second_commit" ]] || fail 'Fixture HEAD did not change'
[[ "$(build_metadata ALERA_BUILD_COMMIT=unknown)" == "$stable_metadata" ]] || \
  fail 'Stable check metadata changed with HEAD'
assert_contains "$(build_metadata)" "cargo:rustc-env=ALERA_BUILD_COMMIT=$second_commit"
assert_contains "$(build_metadata ALERA_BUILD_COMMIT=)" "cargo:rustc-env=ALERA_BUILD_COMMIT=$second_commit"
assert_contains "$(build_metadata 'ALERA_BUILD_COMMIT=   ')" "cargo:rustc-env=ALERA_BUILD_COMMIT=$second_commit"

release_metadata="$(build_metadata ALERA_BUILD_COMMIT=release-sha ALERA_BUILD_VERSION=1.2.3)"
assert_contains "$release_metadata" 'cargo:rustc-env=ALERA_BUILD_COMMIT=release-sha'
assert_contains "$release_metadata" 'cargo:rustc-env=ALERA_BUILD_VERSION=1.2.3'
assert_not_contains "$release_metadata" 'cargo:rerun-if-changed='
windows_metadata="$(build_metadata CARGO_CFG_TARGET_OS=windows CARGO_CFG_TARGET_ENV=msvc ALERA_BUILD_COMMIT=unknown)"
assert_contains "$windows_metadata" 'cargo:rustc-link-arg-bin=alera=/STACK:8388608'

mkdir "$stage/bin"
cat > "$stage/bin/git" <<'GIT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ALERA_TEST_GIT_LOG"
exit 1
GIT
chmod +x "$stage/bin/git"
[[ "$(build_metadata PATH="$stage/bin:$PATH" ALERA_TEST_GIT_LOG="$stage/git-calls" ALERA_BUILD_COMMIT=unknown)" == "$stable_metadata" ]] || \
  fail 'Explicit metadata consulted Git'
[[ ! -e "$stage/git-calls" ]] || fail 'Explicit metadata invoked Git'
rm "$stage/bin/git"

# Verify how the real runtime reports the stamps, including unknown check IDs.
cat > "$stage/runtime-identity.rs" <<'RUST'
mod runtime_build_info {
    include!(concat!(env!("ALERA_TEST_REPO_ROOT"), "/rust/alera-cli/src/terminal_host/runtime_build_info.rs"));
}
fn main() {
    println!("{}|{}|{}|{}", runtime_build_info::version(),
        runtime_build_info::build().unwrap_or("unknown"),
        runtime_build_info::release(), runtime_build_info::RUNTIME_SURFACE);
}
RUST
verify_runtime_identity() {
  local commit="$1" version="$2"
  (
    cd "$root/rust"
    env -u ALERA_BUILD_VERSION ALERA_BUILD_COMMIT="$commit" \
      CARGO_PKG_VERSION=0.1.0 ALERA_TEST_REPO_ROOT="$root" \
      "${@:3}" rustc --edition=2021 --crate-name runtime_identity \
      "$stage/runtime-identity.rs" -o "$stage/runtime-identity.exe"
  )
  local expected_release="alera-runtime@$version"
  if [[ "$commit" != unknown ]]; then
    expected_release+="+$commit"
  fi
  [[ "$("$stage/runtime-identity.exe")" == "$version|$commit|$expected_release|runtime" ]] || \
    fail 'Runtime did not report the expected build identity'
}
verify_runtime_identity unknown 0.1.0
verify_runtime_identity unknown 0.1.0 \
  "ALERA_BUILD_VERSION=${stable_metadata##*cargo:rustc-env=ALERA_BUILD_VERSION=}"
verify_runtime_identity "$second_commit" 0.1.0
verify_runtime_identity release-sha 1.2.3 ALERA_BUILD_VERSION=1.2.3

cat > "$stage/bin/cargo" <<'CARGO'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' "${ALERA_BUILD_COMMIT-unset}" "${ALERA_BUILD_VERSION-unset}" "$*" >> "$ALERA_TEST_CARGO_LOG"
CARGO
chmod +x "$stage/bin/cargo"
run_test_script() {
  PATH="$stage/bin:$PATH" ALERA_TEST_CARGO_LOG="$1" \
    ALERA_BUILD_COMMIT=caller-sha ALERA_BUILD_VERSION=caller-version \
    bash "$root/tool/ci/run_rust_workspace_tests.sh" "${@:2}"
}
run_test_script "$stage/test-calls"
run_test_script "$stage/build-calls" --no-run
test_calls=()
build_calls=()
while IFS= read -r call; do test_calls+=("$call"); done < "$stage/test-calls"
while IFS= read -r call; do build_calls+=("$call"); done < "$stage/build-calls"
[[ "${#test_calls[@]}" == 2 && "${#build_calls[@]}" == 2 ]] || \
  fail 'Expected two workspace invocations per mode'
for index in 0 1; do
  assert_contains "${test_calls[$index]}" $'unknown\tunset\ttest --workspace --locked '
  assert_contains "${build_calls[$index]}" ' --no-run '
  assert_not_contains "${test_calls[$index]}" ' --no-run '
  assert_not_contains "${build_calls[$index]}" ' --test-threads='
  normalized_test="${test_calls[$index]// -- --test-threads=1/}"
  normalized_build="${build_calls[$index]// --no-run/}"
  [[ "$normalized_test" == "$normalized_build" ]] || fail 'Warming changed Cargo selectors'
done
assert_contains "${test_calls[0]}" ' --lib --bins '
assert_not_contains "${test_calls[0]}" ' --test orchestration_review_regressions'
assert_contains "${test_calls[1]}" ' --test orchestration_review_regressions -- --test-threads=1'
if run_test_script "$stage/invalid-calls" --invalid > /dev/null 2>&1; then
  fail 'Unknown mode was accepted'
else
  [[ "$?" == 64 ]] || fail 'Unknown mode did not return usage error'
fi
[[ ! -e "$stage/invalid-calls" ]] || fail 'Unknown mode invoked Cargo'

# A native Cargo probe lets the real make recipe run with no Bash on PATH.
cat > "$stage/cargo-probe.rs" <<'RUST'
use std::io::Write;
fn main() {
    let mut log = std::fs::OpenOptions::new().create(true).append(true)
        .open(std::env::var("ALERA_TEST_CARGO_LOG").unwrap()).unwrap();
    writeln!(log, "{}\t{}\t{}", std::env::var("ALERA_BUILD_COMMIT").unwrap_or_default(),
        std::env::var("ALERA_BUILD_VERSION").unwrap_or_default(),
        std::env::args().skip(1).collect::<Vec<_>>().join(" ")).unwrap();
}
RUST
(
  cd "$root/rust"
  rustc --edition=2021 --crate-name cargo_probe "$stage/cargo-probe.rs" -o "$stage/cargo-probe.exe"
)
make_bin="$(command -v make)"
run_local_make() {
  (
    cd "$root"
    PATH="$stage/bin" ALERA_TEST_CARGO_LOG="$1" \
      ALERA_BUILD_COMMIT=caller-sha ALERA_BUILD_VERSION=caller-version \
      "$make_bin" --no-print-directory --silent -f "$root/makefile" \
      "CARGO=$stage/cargo-probe.exe" "${@:2}"
  )
}
run_local_make "$stage/local-calls" rust-test \
  ALERA_BUILD_COMMIT=command-line-sha ALERA_BUILD_VERSION=command-line-version
local_calls=()
while IFS= read -r call; do local_calls+=("$call"); done < "$stage/local-calls"
[[ "${#local_calls[@]}" == 3 ]] || fail 'Local checks did not run fmt, clippy and tests'
[[ "${local_calls[0]}" == $'unknown\t\tfmt --check' ]] || fail 'Local fmt identity was not isolated'
[[ "${local_calls[1]}" == $'unknown\t\tclippy --workspace --all-targets -- -D warnings' ]] || \
  fail 'Local clippy changed its graph or identity'
[[ "${local_calls[2]}" == $'unknown\t\ttest --workspace' ]] || fail 'Local tests changed their graph or identity'
run_local_make "$stage/cli-calls" cli-build
assert_contains "$(cat "$stage/cli-calls")" $'caller-sha\tcaller-version\trun --quiet --locked '
echo 'Rust build cache contracts passed.'

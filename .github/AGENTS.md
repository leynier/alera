# AGENTS

## Scope

This file applies to GitHub metadata and GitHub Actions workflows.

## Workflow Policy

- Release jobs must be reproducible from a clean checkout.
- Build jobs must run on native runners for their platform.
- The shared job prologue lives in the composite action `.github/actions/setup-flutter-workspace`. Jobs must consume it rather than repeating the steps inline, so the sequence stays identical across `pr.yml`, `desktop-build.yml`, `release-cut.yml`, and `warm-cache.yml`. `actions/checkout` stays in the workflow, because a local composite action cannot be resolved before the repository is on disk.
- Any job that builds the desktop app or runs the Linux desktop integration tests must set up the pinned Rust toolchain (matching `rust/rust-toolchain.toml`) and the Rust build cache before the Flutter build, because the native build hooks compile the Rust `alera` terminal-host sidecar via `cargo build --locked`. Pass `rust: 'true'` to the composite action, which orders the steps correctly.
- Flutter jobs that can run native asset hooks must set up Zig 0.15.2, restore the native asset cache, apply the temporary native asset CI workarounds, and run the native asset preflight before longer test/build commands. This keeps clean runners resilient when `ghostty_vte`, PDFium, or `portable_pty` prebuilt downloads are missing or transiently unavailable. This is the composite action's `native-assets` / `preflight` default.
- Workflows must check out with `submodules: false` and initialize only the submodules the job builds against, via `.github/actions/init-required-submodules`, before dependency resolution. The eight `reference_projects/*` submodules are contributor reading material excluded from analysis, and cloning them costs 649 MB per job. The initialization must stay `--recursive`, because `third_party/dart_terminal` nests the `ghostty` submodule and the native asset cache key hashes a file inside it: without `--recursive`, `hashFiles()` does not fail, it silently hashes a different set.
- The native asset cache key must stay keyed only on `runner.os`, `runner.arch`, and the hashed inputs. Namespacing it per job or per platform produces several copies of byte-identical content that compete for the repository cache budget.
- The Flutter version must stay pinned in the composite action rather than floating on `channel: stable`, so a Flutter release does not invalidate the SDK cache for every job on every platform at once, including the warm cache on `main`.
- `warm-cache.yml` exists to populate the `main` cache scope, because Actions caches are scoped per ref and the pull request workflows only ever write to their own `refs/pull/N/merge` scope. It must keep using the same composite action as the pull request jobs, so the keys match exactly and pull requests restore primary hits instead of paying to save private copies. It must keep running the real release build, since a prologue-only warm job would leave the Rust build cache cold.
- The Flutter test job is sharded by test file through `tool/ci/select_test_shard.dart`, never through `flutter test --total-shards/--shard-index`. That flag slices the tests inside each suite after the suite has been loaded, so every shard would still compile every test file and the split would buy nothing. The `TEST_SHARDS` workflow env, the number of shard entries in the matrix, and the `--expect-inputs` argument of the coverage gate must stay in agreement, otherwise a lost shard silently shrinks the totals.
- Pull request workflows must not rerun solely because a draft pull request becomes ready for review; the existing checks for the same commit remain authoritative.
- Pull request workflows must declare a `concurrency` group keyed by `${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}` with `cancel-in-progress: true`, so a new commit cancels the superseded run instead of leaving it to saturate the shared runner pool. `release-cut.yml` is deliberately excluded: it keeps its own `release-cut` group with `cancel-in-progress: false`, because cancelling mid-publish would expose a partial release.
- Do not expose partial releases to users.
- `release-cut.yml` is the single manual release entry point. It must plan desktop and mobile independently, skip unchanged products, and preserve their separate version and tag sequences.
- Release automation must publish drafts first, verify required assets and update manifests, then publish public releases.
- Release notes must be product-scoped via `tool/release/generate_release_notes.dart` (desktop excludes `mobile/` and `landing/`; mobile includes only `mobile/`), and only desktop stable releases may carry the Latest badge.
- Release workflows must not push release commits or tags until platform artifacts and update manifests have been generated and verified.
- Update indexes must be deployed only after the corresponding GitHub Release is public.
- Existing stable and release-candidate update indexes must be preserved when publishing the other channel; ignore only confirmed first-time 404 responses.
- Stable release jobs must not enable automatic installation until signing and notarization or trust are configured for the relevant platform.
- Release jobs must sign schema v2 update indexes before publication and verify the manifest signature before upload.
- Linux release jobs must publish signed APT and RPM repository metadata when Linux packages are included.
- Signing secrets must be scoped only to release jobs that need them.

## Issue And PR Policy

- Issue templates should collect platform details when behavior may differ across macOS, Windows, and Linux.
- Pull request templates should require validation notes, platform notes, and security/update risk notes when relevant.
- Workflow-created labels must be created idempotently when they may not exist in a fresh public repository.

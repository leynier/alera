# xterm2 migration validation

## Scope and pinned sources

Desktop and mobile now use `xterm2` 5.3.0 from the existing `third_party/xterm` path. The fork starts at `SoFluffyOS/xterm2@2a339558ba103e38a304a4eda7c984b45c47e186`. Its Unicode 17/grapheme handling, Kitty keyboard protocol, synchronized updates, native OSC 8 metadata and parser optimizations remain active. Alera keeps its own search and keyboard dispatch; xterm2's additional navigation shortcuts are not installed.

| Fork | Final `next` SHA | Purpose |
| --- | --- | --- |
| `leynier/xterm2` | `45d341383e4d4e137c7e70efad0441babd74c561` | Upstream base plus focused compatibility, regression tests and renderer cache optimization |
| `leynier/xterm.dart` | `dd37dbe3cb0ea5f2de529ba158395af062351e62` | Preserves legacy code through `14ebe14844b5f35cff20c582f09fd97dd6bedc28`, plus branch policy and CI documentation |
| `leynier/dart_terminal` | `7bfb6c57f8da75742891ac27b568cc651f77501a` | Preserves `dca082113f7e7a04d465431440a765e71468d3ee`, plus branch links and workflow updates |

There is no SDK upgrade, Ghostty renderer migration, pub.dev publication or Alera release. The consumed `dart_terminal:next` is not updated to upstream 0.2.0-beta.2 and does not acquire `native_prebuilt` or a Dart 3.13 requirement. Its nested Ghostty stays at `08f039fbb3dea9c6b1cdb5ff4550666598122346`. Its separate `master` mirror tracks current upstream without changing this pin.

## Compatibility decisions

The [21-change preservation matrix](../third_party/xterm/ALERA_PATCHES.md) identifies every original correction as ported, retained or superseded by upstream and names its regression tests. The old commits were not cherry-picked wholesale.

- Desktop explicitly disables reflow with a hidden cursor to retain the current TUI resize behavior; mobile explicitly enables it while restoring host-sized history to a phone viewport. Saved cursor coordinates, pending wrap, narrow/wide rows, scroll regions, styled erasure and repaired short rows have regression coverage.
- Scrollback compaction preserves combining marks, wide-cell placeholders, hyperlink IDs and underline metadata. Copying blank columns preserves spaces without inserting spaces after wide glyphs or changing tab expansion.
- Injected clipboard callbacks, contextual Ctrl+C, Shift selection during mouse reporting, wheel sensitivity, font weight and cursor blink settings remain available. Unnegotiated Shift+Enter retains CSI-u; negotiated Kitty/modifyOtherKeys behavior stays upstream.
- OSC 8 links use native cell metadata instead of a second anchor tracker. Text URL detection, allowed URI schemes and activation modifiers remain in Alera, with tests for wrapping, overwrite, scrollback eviction and graphemes.
- Native OSC 52 callbacks use Alera's strict decoder: existing permission gate, explicit selector validation, 128 KiB encoded-payload limit and no clipboard reads. Alera disables iTerm2 and Kitty clipboard extensions and supplies an explicit deny callback for clipboard queries. Mobile explicitly denies both remote clipboard callbacks, preventing TerminalView from installing system defaults.
- Closing or replacing an emulator calls `Terminal.dispose()` in desktop and mobile, including snapshot rebuilds and reconnects. This cancels xterm2 timers and releases its additional resources.
- The renderer keeps a bounded 2,048-entry paragraph cache with explicit native paragraph disposal. Linked LRU promotion and a plain ASCII cache hit avoid repeated hash removal/insertion and decoration work; styled/Unicode/selection rendering keeps the general path.

## Test evidence

Local application validation uses isolated Flutter 3.44.8 / Dart 3.12.2 without changing the global Flutter installation. Raw logs and recovery bundles are retained in `/home/leynier/.codex/artifacts/alera-terminal-forks-20260829-6e04/`; local working logs are under ignored `build/terminal-migration/`.

| Check | Result |
| --- | --- |
| xterm2 upstream baseline | 742 passed, two skipped, two existing text-scaler golden failures |
| xterm2 fork | 863 non-golden tests passed, two skipped; static analysis clean |
| xterm2 CI | [Final pinned commit CI](https://github.com/leynier/xterm2/actions/runs/33293168080) passed on Linux, macOS and Windows using Flutter 3.44.8 |
| Alera desktop suite | Final complete run: 3,356 passed, one skipped (`flutter test --concurrency 2`) |
| Alera mobile suite | 576 passed against the reviewed pin with concurrency two, including focused clipboard denial and lifecycle/reconnect assertions |
| Static analysis | Complete desktop and mobile analysis clean |
| Link regressions | 14 passed, including native OSC 8 overwrite/reflow and grapheme URL offsets |
| dart_terminal build/cache tests | 25 passed from the package directory |
| dart_terminal CI | Analyze and PTY passed; [VTE build/test matrix](https://github.com/leynier/dart_terminal/actions/runs/33290141457) passed after retrying one transient Zig TLS download failure in Android ARM |
| Native asset integrity | All 12 extracted native release binaries match the SHA-256 values in `asset_hashes.dart` |
| Repeated Ghostty source builds | Two successful native hook runs; nested Ghostty checkout remains unchanged |
| Linux native application | Built successfully and ran all three integration benchmark executables |
| macOS native input | 10 xterm interaction tests and 145 Alera terminal/input/link/widget tests passed against final sources |
| Windows native input | 10 xterm interaction tests and 143 Alera terminal/input/link/widget tests passed against final sources; two platform-specific tests skipped |
| Windows native application | Full debug build and final-source incremental build passed, including the Rust library and CLI sidecar |
| Android build | Debug APK built successfully, including its native Rust library |
| macOS / iOS builds | Blocked by missing CocoaPods on the Mac; no machine-wide installation was performed |

The two upstream text-scaler golden tests retain their original images and are tagged `platform-golden`. CI gates all other tests and runs those goldens in a separate non-blocking step; unfiltered `flutter test` still reports their failures. They are not presented as passing checks.

The initial branch-policy commits changed documentation and the disabled autotag workflow only. The platform build/input checks above predate the review corrections below; those application fixes are validated by Linux-hosted Flutter tests. The dart_terminal runtime remains identical to `e7028139cd90a0676c0323b2ec5f4312d14c4932`.

For a repeatable local check, activate Flutter 3.44.8 only in the current process environment, initialize submodules, and run these commands from the indicated package directories. Native builds also require the project's platform toolchains; the Mac currently lacks CocoaPods.

| Directory | Commands |
| --- | --- |
| Repository root | `flutter pub get`, `flutter analyze --no-pub`, `flutter test --concurrency 2` |
| `third_party/xterm` | `flutter pub get`, `flutter analyze --fatal-infos`, `flutter test --exclude-tags platform-golden` |
| `mobile` | `flutter pub get`, `flutter analyze --no-pub`, `flutter test`, `flutter build apk --debug` |
| `third_party/dart_terminal/pkgs/vte/ghostty_vte` | `flutter pub get`, `flutter test test/hook_build_test.dart test/build_cache_test.dart` |

On Linux, run each benchmark separately with `xvfb-run -a flutter test integration_test/<benchmark>.dart -d linux --reporter expanded`, using `terminal_render_benchmark`, `terminal_flush_cadence_benchmark` and `terminal_restore_benchmark`. Stop this task's other builds first and record host load; do not stop another task's processes to obtain a quieter sample.

An earlier parallel desktop suite run had an isolated failure in `mobile_emulator_playback_monitor_test.dart: reports player errors without treating them as completion` (expected one event, observed zero). All five tests in that file passed on isolated retry, and the final complete run with concurrency two passed all 3,353 tests. No unrelated playback implementation or test was changed. Automated widget/protocol tests do not substitute for interactive IME, clipboard/image, gesture or device smoke testing.

## Performance and memory

The following are Linux debug/Xvfb observations from the existing benchmarks, not release-mode performance guarantees. CPU is percent of one core. Workload, viewport and Alera's production pacing settings are unchanged.

| Render workload | Legacy build / raster median | xterm2 final cache build / raster median | Legacy / xterm2 CPU |
| --- | --- | --- | --- |
| No output | 0.40 / 2.07 ms | 0.42 / 2.06 ms | 64.0% / 64.4% |
| One line per frame | 2.68 / 6.32 ms | 3.29 / 6.07 ms | 125.9% / 119.6% |
| One screenful per frame | 2.61 / 6.17 ms | 2.36 / 6.33 ms | 127.0% / 123.4% |

Initial xterm2 runs reproducibly increased build medians to approximately 4.7-5.3 ms. The paragraph-cache changes reduce that cost; one-line build time is still about 23% above the recorded legacy median, while raster medians and CPU are comparable. This residual debug result is disclosed rather than treated as proof of performance equivalence. A later final-pin repeat measured build medians 0.42 / 3.54 / 2.58 ms and raster medians 2.27 / 7.43 / 7.51 ms for the three workloads, respectively; that run was on the contended host described below.

The snapshot replay benchmark restored 2,560,000 bytes with a 1 MiB live backlog. A repeat against the final pinned cache implementation also passed all five runs (median 2,510 ms, maximum 2,657 ms, 40 flushes each), despite concurrent compilation/test activity elsewhere on this 16-core host. Legacy median was 3,052 ms (maximum 3,165 ms; two of five runs within the 3,000 ms target). The xterm2 compatibility run measured 2,118 ms (maximum 2,186 ms; all five within target), with 40 flushes in every run and throughput increasing from 0.80 to 1.15 MiB/s. CPU increased from 53.1% to 158.2% while the restore completed sooner; this measurement does not establish an energy reduction. The baseline emitted its measurements but failed teardown because live backlog left a scheduled callback; the benchmark now disposes its runtime before the binding's final checks, and the migrated run passed.

Before the final cache optimization, the cadence benchmark measured 18.7 versus 18.1 flushes/s and CPU 181.2% versus 180.7%, but raster median increased from 7.93 to 13.28 ms. Two later final-cache runs passed functionally but overlapped substantial compilation/test activity in other worktrees (33 then 30 input writes/s versus 74 at baseline, 35.02 then 47.91 ms raster; host load approximately 35 on 16 cores). They are not controlled comparisons and must not be used to attribute a regression to xterm2. Production pacing constants were not changed. Re-run cadence/restoration on an idle machine for a reliable final performance sign-off.

An identical 20,000-line short-output scenario retaining 10,000 rows measured 687,616 bytes in cell backing buffers for both forks, unchanged after resizing 120 to 80 columns. This measures retained typed cell buffers only, not total process heap, native paragraphs or hyperlink-table memory. Compaction tests separately cover hyperlink and grapheme metadata preservation.

## Review corrections

A Codex review using `gpt-5.6-sol` with high effort against `origin/main` found three reproducible issues that the initial tests missed. The fixes passed 3,356 desktop tests (one skip), 576 mobile tests, and 863 fork tests (two skips, excluding the two inherited goldens), plus static analysis and fork CI on Linux/macOS/Windows. The review fixes preserve the migration policy:

- Focused xterm2 views install system clipboard handlers when callbacks are unset. Desktop now explicitly denies queries while retaining gated writes; mobile explicitly denies both. Mounted, focused-view tests cover desktop permissions and mobile emulator replacement.
- The generic 8 KiB OSC parser cap prevented larger authorized copies from reaching Alera's decoder. OSC 52 now permits the existing 128 KiB encoded payload after a bounded header, rejects extra fields, and preserves parser recovery across BEL/ST overflow boundaries. Other OSC sequences keep their original cap. A separate switch disables OSC 5522 in Alera, so it cannot bypass the policy limiting supported clipboard protocols.
- At 4,096 retained native hyperlinks, upstream scanned both buffers for each subsequent allocation. Pruning now waits 256 rejected allocation attempts between scans, including when a scan reclaims only one slot. Storage remains bounded and referenced links remain intact; reclaiming erased links can lag by that bounded number of attempts. Regression tests cover eventual recovery and reset.

The same 7,000-link scenario measured roughly 278-300 ms per 1,000 links after capacity before the fix and 4-25 ms afterward. This is a targeted parser benchmark, not a substitute for the render/cadence measurements above. Reproduce it from the fork with `dart run script/hyperlink_capacity_benchmark.dart`.

An additional mobile full-suite run intermittently failed `A closed socket ends both streams` in `mobile_runtime_terminal_client_test.dart`; all eight cases passed in isolation, and the complete 576-test suite then passed with concurrency two. The socket implementation and its tests were not changed.

The shared Puro Flutter 3.44.8 environment was removed externally during the review's first full desktop run, causing missing `flutter_tester` errors. That interrupted run is not a validation result. Subsequent review commands use a task-owned Flutter 3.44.8 / Dart 3.12.2 checkout under the backup directory's `flutter-sdk/`; this task did not change the global Flutter selection.

## Branch conservation and recovery

The [machine-readable manifest](terminal-fork-branches.json) records every previous branch SHA and its conservation proof. All 10 legacy xterm branches are ancestors of its final `next`. Seven dart_terminal branches are divergent only because they were squash-merged: stable patch IDs match their squash commits, those commits are ancestors of `next`, and the generated binding/WASM blobs checked in the ABI update match exactly.

Before changing refs, full Git bundles and branch manifests were saved and verified. The two old `next` branches were fast-forwarded, default branches changed to `next`, and automatic deletion after merge enabled. Initial branch cleanup used atomic pushes and explicit per-ref SHA leases after rechecking refs and open PRs. The final requested policy retains `master` as an upstream mirror alongside `next`; all other branches were removed. Tags, releases and repositories were preserved; the legacy fork was not archived.

Each repository now has exactly `master` and `next`, with `next` as default. Active deletion-only rulesets protect both branches without preventing mirror updates. The inherited autotag workflow is disabled in both xterm forks before restoring their mirrors, preventing sync pushes from generating tags. `dart_terminal` retains its 20 existing tags and two releases; no upstream tags were pushed.

| Fork mirror | Upstream | Verified mirror SHA |
| --- | --- | --- |
| `leynier/xterm.dart:master` | `TerminalStudio/xterm.dart:master` | `d35ba2cc72d0b89b0fd19af69d57df2c02f26a16` |
| `leynier/xterm2:master` | `SoFluffyOS/xterm2:master` | `2a339558ba103e38a304a4eda7c984b45c47e186` |
| `leynier/dart_terminal:master` | `kingwill101/dart_terminal:master` | `3146f58d2b675d50383c86b5b5eb5d89e6c1058c` |

Select `master` explicitly when syncing a fork. Merging upstream into `next` requires separate review, especially for the deferred dart_terminal SDK upgrade. The backup's `mirror-final-state.json` records live branch SHAs, rulesets, workflow state and preserved tag/release inventories.

The external backup directory contains `xterm-original.bundle`, `dart-terminal-original.bundle`, final bundles for all three forks, before-delete manifests, conservation proofs and GitHub inventory snapshots. A fresh recovery repository can import a bundle's refs without contacting GitHub:

```sh
git init recovered-fork
git -C recovered-fork fetch /absolute/path/to/fork.bundle '+refs/*:refs/recovery/*'
git -C recovered-fork branch recovered-change <sha-from-manifest>
```

Restore remote refs only deliberately, after checking for subsequent changes. Alera pins immutable gitlink commits, so ordinary submodule initialization does not require any deleted branch.

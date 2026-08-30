# Performance

Alera treats performance as a product contract. Optimization work starts with a reproducible profile capture, changes one bounded subsystem at a time, and verifies both timing and behavior before tightening a budget.

## Current Guardrails

- Shell and sidebar consumers select only the state they render; rapidly changing agent status is isolated below stable shell widgets.
- Resize gestures keep transient dimensions locally and persist them once at drag end.
- Markdown editor updates are indexed by workspace path and coalesced to one frame callback.
- Filesystem watchers prefer native events, use low-frequency polling only as a recovery watchdog, and discard generated/build-tree churn before it reaches Dart.
- The explorer computes one Git status snapshot per workspace refresh and reuses it for expanded directories.
- Obsolete workspace searches are cancelled in Rust as soon as the query generation changes.
- Bundled Inter and JetBrains Mono assets remove runtime font-network and font-loader work.
- Terminal output is batched, byte-bounded in the host, character-bounded before Flutter rendering, and recovered from the host's per-client delivery cursor when a client falls behind, so a tab switch or a backpressure resync costs the bytes that were missed rather than a replay of the scrollback. A cold attach still replays, capped to what the emulator will keep. Restore and control segments are protected from the live-output backlog cap, and restore progress advances only for snapshot characters that reached the emulator. Per-client terminal sequence watermarks keep output included in an attachment snapshot before its control response and later output after it. RPC responses and runtime events use a separate control lane so terminal backpressure cannot disconnect the workbench.
- Terminal output flushes are paced by a cadence floor (50 ms), so a process writing without pause cannot drive the frame loop at full vsync. The floor is measured from the moment a frame is requested, not from the flush that follows, or the vsync wait would be charged to the next interval too. A terminal that has been quiet still flushes on the very next frame, so echo latency while typing is unchanged. Delivery and frame scheduling park while the desktop window is hidden and resume from the host's delivery cursor.
- The terminal memory budget counts the allocated typed-data capacity of every xterm line, including capacity retained after a viewport shrink. Only panes currently on screen are pinned, so off-screen tabs in the active workspace obey the same budget as other cold terminals and restore from the host when selected again.
- xterm buffer rows are compacted the moment they scroll into history: the trailing all-zero capacity every row keeps for in-place edits is released, so a 10,000-line scrollback costs what its text actually occupies instead of `lines x columns x 16` bytes. Cells holding only a styled erase survive, wide-character placeholders are kept, and a history row that re-enters the viewport regrows with zero cells. A width resize re-compacts the rebuilt history. The parser also decodes input into preallocated code-point blocks instead of `String.runes.toList()`, and the painter reuses one `Paint` for solid rectangles, so sustained output allocates less on the UI isolate.
- Recurring pollers whose results nobody can see while the window is hidden park through `ForegroundParkedRefresh` (`lib/src/features/app_window/domain/foreground_parked_refresh.dart`): the resource snapshot and runtime host status probes stop their cadence on hide and refresh immediately on return, mirroring the update check scheduler. Stopping the resource poll is also what lets the sidecar's demand-driven sampler go idle.
- The workbench body watches agent status per terminal session of the visible workspace rather than the whole status map, so an agent transition in another workspace no longer rebuilds the active workbench tree.
- The mobile terminal retains its 33 ms sustained-output cadence. Its restore queue advances an offset inside each original chunk instead of allocating the remaining tail after every 64 KiB frame, preserves snapshots separately from the bounded live backlog, and releases the raw snapshot bytes once xterm owns the decoded restore.
- The mobile gateway gets a deeper terminal lane than the desktop socket, because a WAN send can stall for hundreds of milliseconds and the queue depth the local socket was tuned for turns one stall into a permanent pause. Depth only buys time: the mobile client answers the host's backpressure resync the same way the desktop does, which is what actually clears the pause.

## Linux Startup Harness

Run:

```bash
make perf-linux
```

This launches a Linux profile build five times with `ALERA_PERF_TRACE=true`. The report at `.dart_tool/performance/startup_linux.json` contains every trace record, per-run normalized metrics, and median/p95/p99/MAD summaries for `runApp`, first-frame presentation, and first-frame build/raster/total duration.

The checked-in `tool/performance/linux_startup_budget.json` is a calibration ratchet. The default command reports violations without failing so measurements from different developer hardware remain informative. Pass `--enforce` only on a stable, comparable runner. PR CI captures three non-blocking samples under Xvfb and uploads the report for trend inspection.

## macOS Resource Harness

Run the desktop app with release-like runtime characteristics and compile-time performance tracing:

```bash
make app-profile
```

In another terminal, capture a named scenario:

```bash
PERF_SCENARIO=idle PERF_DURATION_SECONDS=30 PERF_APP_PID=<profile-pid> make perf-macos-resources
```

The report under `.dart_tool/performance/resources_<scenario>.json` contains 250 ms samples and median, p95, and maximum CPU, RSS, and process counts. It separates the Alera app, runtime host, Flutter tooling, build runner, terminal descendants, provider CLIs, and the tracked total. Pass `PERF_APP_PID` whenever a Debug and Profile instance can coexist so the capture cannot select the wrong process.

Capture idle, a common workbench flow, a terminal-output burst, a quota refresh, and representative agent launches independently. Do not run `build_runner` during final captures. Its memory is development tooling and must be reported separately from the shipped app.

The latest detailed macOS investigation and before/after results are recorded in [`performance-resource-profile-2026-07-19.md`](performance-resource-profile-2026-07-19.md).

## Resource Sampling Cadence

The sidecar's own process-table sweep is demand-driven: nothing samples until a client asks, and the ticker stops itself once they stop asking. The cadence is not fixed in the host. Each `resources.snapshot` request states the interval the caller polls at (`intervalMs`), and the host both samples at that interval and sizes its idle window around it. Closing the resource panel therefore makes the host proportionally cheaper rather than merely making the app ask less often.

Deriving the idle window from the stated cadence is what keeps it correct. When it was a fixed constant it had to agree with a polling interval chosen in Dart, the two drifted, and the ticker stopped under a chip that was still polling on time - which is what made the panel appear to work only while hovered. A client that states nothing gets the host's own defaults, so an older app is unaffected.

## Where A Frame's CPU Goes On Linux

Measured on a Wayland session with an Intel Arc GPU, Flutter 3.44.8, with `perf` at thread granularity against the installed release build while agents streamed into a visible terminal:

| thread | share of app CPU | what it is doing |
| --- | --- | --- |
| platform (`alera`) | 42.8% | pixman and `__memmove_avx`/`__memset_avx`; 23% of its samples are inside `gdk_cairo_draw_from_gl` |
| `io.flutter.raster` | 27.7% | the Flutter engine drawing |
| Rust threads | ~18% | the filesystem watcher and git work (sha1, zlib) |

`gdk_cairo_draw_from_gl` is GTK3 drawing a GL texture into a cairo context. When it cannot blit directly it reads the rendered surface back to RAM and composites it in software, so its cost scales with the window's pixels rather than with what changed on screen. `GDK_BACKEND=x11`, `GTK_CSD=0` and `GDK_GL=gles` were each measured against the default and all four landed within noise of one another (37-41% of a core), so this is not avoidable from the app side.

The lever that is available is the number of frames. CPU tracks the frame count almost linearly, and a frame that changes nothing still costs about 6 ms of CPU, so producing fewer frames is worth more than making any one of them cheaper. That is why the terminal has a flush cadence floor, and why the terminal painter was left alone: rendering a full screen of streaming text is 2.7-3.1 ms of raster out of 15-21 ms of CPU per frame.

Two benchmarks back this up, both on a real device (Xvfb works but rasterizes in software, so its numbers only compare against other Xvfb runs):

```bash
flutter test integration_test/terminal_render_benchmark.dart -d linux
flutter test integration_test/terminal_flush_cadence_benchmark.dart -d linux
```

The first drives xterm directly and pumps its own frames, reporting what a frame costs (`BENCH_PUMP_MS` sets the cadence). The second feeds output through `XtermTerminalRuntime` and lets the runtime schedule the flushes, reporting flushes per second and process CPU. The 2026-08-01 five-sample comparison reduced the median from 29.0 to 19.5 flushes/s and from 89.9% to 76.7% of one core. Neither is a pass/fail test; run one before and after a rendering change and compare.

## Flutter 3.47 Linux Renderer

Linux explicitly retains Skia in `linux/runner/my_application.cc`. Flutter 3.47 enables Impeller by default, but the upgrade comparison on the development machine found substantially higher terminal CPU and raster time. This uses Flutter's [supported Linux renderer opt-out](https://docs.flutter.dev/perf/impeller); macOS, Windows, and mobile retain their SDK defaults.

The initial comparison used Flutter 3.44.8 and 3.47.2, the same xterm2 revision (`45d34138`), native Linux debug builds, a 162x44-cell terminal, the default 16 ms pump delay, and five eight-second samples per scenario. Values below are medians; CPU is a percentage of one core, not the whole machine.

| Scenario | 3.44.8 CPU | 3.47.2 Impeller CPU | 3.44.8 Raster | 3.47.2 Impeller Raster |
| --- | ---: | ---: | ---: | ---: |
| One line per frame | 47.1% | 84.2% | 4.67 ms | 15.77 ms |
| One screenful per frame | 53.0% | 91.3% | 5.71 ms | 16.92 ms |
| Runtime flush cadence | 65.6% | 116.9% | 5.57 ms | 13.40 ms |

The host is an Intel Core Ultra 9 285H with 16 logical CPUs and Intel graphics on Ubuntu 26.04.1 / Mesa 26.0.8. It is a shared development desktop, not a dedicated benchmark runner. Separate SDK batches showed appreciable variation, so the final comparison alternates SDK order and reports raw samples, medians, and MAD. The no-output render scenario deliberately pumps frames; it must not be presented as idle application CPU. Final comparison results and their source revision are recorded in [upgrade PR #585](https://github.com/leynier/alera/pull/585). Keep the existing three-second restore target and investigate reproducible median CPU or latency regressions above 10% without changing benchmark budgets.

## Terminal Restore Harness

Run:

```bash
flutter test integration_test/terminal_restore_benchmark.dart -d linux
```

The benchmark mounts and starts `TerminalSurface` before timing, sends the default 2.56 MB snapshot with 420,000 ANSI escape characters, immediately follows it with a 1 MiB live-output backlog, and waits through the framework post-frame callback after the restore overlay is removed. It discards one warm-up and reports five measured replays, including accepted, first-chunk and framework post-frame latency, flushes, CPU, build and raster timings. The boundary starts when the snapshot event reaches Flutter, so it isolates the replay bottleneck and intentionally excludes tab selection, host attachment, storage and transport.

On the Linux development machine with Flutter 3.44.8 and the 20 Hz sustained-output cadence, the protected restore queue completed all five samples within the three-second target: 2,074.59 ms median, 2,369.25 ms p95 and maximum, 6.58 ms MAD, and exactly 40 flushes per restore. The three-second target is scoped to the default 10,000-line, 2.56 MB replay budget. Larger user-configured histories preserve their additional content and scale with payload size. This is a comparison benchmark rather than a timing assertion because desktop hardware and display composition materially affect the result.

## Quick Open Search Harness

Run the non-gating 40,000-path Quick Open benchmark on Linux:

```bash
flutter test integration_test/quick_open_benchmark.dart -d linux
```

The harness creates 40,000 files, starts one snapshot index, verifies that every eligible file was indexed, and sends 100 FRB queries. It reports the scan duration and query p50/p95. The query path measures native indexing and ranking plus the FRB call, while the dialog itself is covered by `test/widget/quick_open_dialog_test.dart`; compare results on the same machine and Flutter revision. The working tree is temporary and is removed after the run.

## Codex Chat Timeline Harness

Run the non-gating long-thread benchmark on Linux:

```bash
flutter test integration_test/codex_chat_timeline_benchmark.dart -d linux
```

The harness mounts a 240-turn Codex thread, verifies that slivers build only the visible subset, then delivers 120 incremental assistant updates through the runtime event path. It reports initial mount time and p50/p95 build and raster durations. Compare results on the same machine and Flutter revision; timing is informational because display composition and debug/profile mode materially affect the result. Widget and Rust tests separately enforce delta identity preservation and snapshot-delta correctness.

On the Linux development machine on 2026-08-04, the focused optimization run built 5 of 240 timeline turns. Reusing unchanged entry widgets reduced Debug build duration from 29.22 ms p50 and 41.38 ms p95 to 2.35 ms p50 and 5.45 ms p95; raster duration remained within noise at 0.63 ms p50 and 1.50 ms p95. These values are a same-machine comparison, not a portable budget.

## Measurement Rules

- Compare before and after on the same machine, Flutter revision, build mode, display setup, and power mode.
- Use at least five samples for optimization decisions; use median for typical latency, p95/p99 for tail latency, and MAD for run noise.
- Treat a first-frame total above 16.7 ms as a missed 60 Hz frame and above 8.3 ms as a missed 120 Hz frame.
- Keep tracing compile-time gated. `ALERA_PERF_TRACE` is false in ordinary builds, so instrumentation does not format records or emit timeline events in production.
- Attribute child-process RSS to the CLI or terminal workload that owns it. Do not present Flutter JIT, `flutter run`, build hooks, or `build_runner` memory as shipped application memory.
- Prefer eliminating work, narrowing invalidation, batching, cancellation, and bounded queues before protocol or architecture changes.
- Change the terminal JSON protocol only after profiling shows serialization costs at least 2 ms per frame or 20% of the measured hot path; current evidence does not meet that gate.

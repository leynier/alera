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
- Terminal output flushes are paced by a cadence floor (33 ms), so a process writing without pause cannot drive the frame loop at full vsync. The floor is measured from the moment a frame is requested, not from the flush that follows, or the vsync wait would be charged to the next interval too and pace the terminal at 20 Hz instead of 30. A terminal that has been quiet still flushes on the very next frame, so echo latency while typing is unchanged.
- The mobile terminal uses the same 33 ms sustained-output cadence. Its restore queue advances an offset inside each original chunk instead of allocating the remaining tail after every 64 KiB frame, preserves snapshots separately from the bounded live backlog, and releases the raw snapshot bytes once xterm owns the decoded restore.
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

The first drives xterm directly and pumps its own frames, reporting what a frame costs (`BENCH_PUMP_MS` sets the cadence). The second feeds output through `XtermTerminalRuntime` and lets the runtime schedule the flushes, reporting flushes per second and process CPU: 60.0 flushes/s and ~100% of a core before the cadence floor, 29.1 flushes/s and ~80% after. Neither is a pass/fail test; run one before and after a rendering change and compare.

## Terminal Restore Harness

Run:

```bash
flutter test integration_test/terminal_restore_benchmark.dart -d linux
```

The benchmark mounts and starts `TerminalSurface` before timing, sends the default 2.56 MB snapshot with 420,000 ANSI escape characters, immediately follows it with a 1 MiB live-output backlog, and waits through the framework post-frame callback after the restore overlay is removed. It discards one warm-up and reports five measured replays, including accepted, first-chunk and framework post-frame latency, flushes, CPU, build and raster timings. The boundary starts when the snapshot event reaches Flutter, so it isolates the replay bottleneck and intentionally excludes tab selection, host attachment, storage and transport.

On the Linux development machine with Flutter 3.44.8, the protected restore queue completed all five samples within the three-second target: 1,373.74 ms median, 1,403.85 ms p95 and maximum, 24.91 ms MAD, and exactly 40 flushes per restore. The three-second target is scoped to the default 10,000-line, 2.56 MB replay budget. Larger user-configured histories preserve their additional content and scale with payload size. This is a comparison benchmark rather than a timing assertion because desktop hardware and display composition materially affect the result.

## Measurement Rules

- Compare before and after on the same machine, Flutter revision, build mode, display setup, and power mode.
- Use at least five samples for optimization decisions; use median for typical latency, p95/p99 for tail latency, and MAD for run noise.
- Treat a first-frame total above 16.7 ms as a missed 60 Hz frame and above 8.3 ms as a missed 120 Hz frame.
- Keep tracing compile-time gated. `ALERA_PERF_TRACE` is false in ordinary builds, so instrumentation does not format records or emit timeline events in production.
- Attribute child-process RSS to the CLI or terminal workload that owns it. Do not present Flutter JIT, `flutter run`, build hooks, or `build_runner` memory as shipped application memory.
- Prefer eliminating work, narrowing invalidation, batching, cancellation, and bounded queues before protocol or architecture changes.
- Change the terminal JSON protocol only after profiling shows serialization costs at least 2 ms per frame or 20% of the measured hot path; current evidence does not meet that gate.

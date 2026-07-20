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
- Terminal output is batched, byte-bounded in the host, character-bounded before Flutter rendering, and recovered from a snapshot when a client falls behind. RPC responses and runtime events use a separate control lane so terminal backpressure cannot disconnect the workbench.

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

Capture idle, a common workbench flow, a terminal-output burst, a quota refresh, and representative agent launches independently. Keep the `build_runner` watcher stopped during final captures. Its memory is development tooling and must be reported separately from the shipped app.

The latest detailed macOS investigation and before/after results are recorded in [`performance-resource-profile-2026-07-19.md`](performance-resource-profile-2026-07-19.md).

## Measurement Rules

- Compare before and after on the same machine, Flutter revision, build mode, display setup, and power mode.
- Use at least five samples for optimization decisions; use median for typical latency, p95/p99 for tail latency, and MAD for run noise.
- Treat a first-frame total above 16.7 ms as a missed 60 Hz frame and above 8.3 ms as a missed 120 Hz frame.
- Keep tracing compile-time gated. `ALERA_PERF_TRACE` is false in ordinary builds, so instrumentation does not format records or emit timeline events in production.
- Attribute child-process RSS to the CLI or terminal workload that owns it. Do not present Flutter JIT, `flutter run`, build hooks, or `build_runner` memory as shipped application memory.
- Prefer eliminating work, narrowing invalidation, batching, cancellation, and bounded queues before protocol or architecture changes.
- Change the terminal JSON protocol only after profiling shows serialization costs at least 2 ms per frame or 20% of the measured hot path; current evidence does not meet that gate.

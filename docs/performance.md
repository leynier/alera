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
- Terminal output is batched, byte-bounded in the host, character-bounded before Flutter rendering, and recovered from a snapshot when a client falls behind.

## Linux Startup Harness

Run:

```bash
make perf-linux
```

This launches a Linux profile build five times with `ALERA_PERF_TRACE=true`. The report at `.dart_tool/performance/startup_linux.json` contains every trace record, per-run normalized metrics, and median/p95/p99/MAD summaries for `runApp`, first-frame presentation, and first-frame build/raster/total duration.

The checked-in `tool/performance/linux_startup_budget.json` is a calibration ratchet. The default command reports violations without failing so measurements from different developer hardware remain informative. Pass `--enforce` only on a stable, comparable runner. PR CI captures three non-blocking samples under Xvfb and uploads the report for trend inspection.

## Measurement Rules

- Compare before and after on the same machine, Flutter revision, build mode, display setup, and power mode.
- Use at least five samples for optimization decisions; use median for typical latency, p95/p99 for tail latency, and MAD for run noise.
- Treat a first-frame total above 16.7 ms as a missed 60 Hz frame and above 8.3 ms as a missed 120 Hz frame.
- Keep tracing compile-time gated. `ALERA_PERF_TRACE` is false in ordinary builds, so instrumentation does not format records or emit timeline events in production.
- Prefer eliminating work, narrowing invalidation, batching, cancellation, and bounded queues before protocol or architecture changes.
- Change the terminal JSON protocol only after profiling shows serialization costs at least 2 ms per frame or 20% of the measured hot path; current evidence does not meet that gate.

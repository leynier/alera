# Performance Evidence

## Environment And Scope

Measurements ran on the same Linux graphical session on 2026-07-30. Flutter used its existing debug integration benchmarks because those are the repository's established end-to-end baselines. GPUI used an optimized build because debug GPUI and terminal parser results are not representative. The comparison is a feasibility gate, not a universal hardware claim.

## Streaming Terminal

Flutter command:

```bash
ALERA_FLAVOR=dev flutter test integration_test/terminal_flush_cadence_benchmark.dart -d linux
```

GPUI command:

```bash
cargo build --release --manifest-path experiments/alera-gpui/Cargo.toml --bin terminal_performance
ALERA_GPUI_BENCH_MODE=stream experiments/alera-gpui/target/release/terminal_performance
```

| Client | Input | Presentation | CPU |
| --- | ---: | ---: | ---: |
| Flutter | 89 writes/s | 29.0 flushes/s, 59.3 binding frames/s | 82.0% of one core |
| GPUI | 120.3 writes/s | 30.1 rendered frames/s | 14.5% of one core |

GPUI used 82.3% less CPU while accepting 35.2% more writes per second. This passes the required 30% CPU reduction by a wide margin.

## Idle Frames

Command:

```bash
ALERA_GPUI_BENCH_MODE=idle experiments/alera-gpui/target/release/terminal_performance
```

GPUI rendered 2 total startup frames over 8.01 seconds and used 1.12% of one core. No frame loop remained active after startup, so the no-sustained-idle-frames gate passes.

## Restore

Flutter replayed a 2,560,000-byte snapshot followed immediately by a 1 MiB live backlog. Its five measured runs reported 1,351.24 ms median, 1,377.26 ms p95 and 40 flushes per restore. All markers and assertions passed, and the benchmark drained the live backlog after the measured interval so teardown also completed successfully.

GPUI replayed the same 2,560,000-byte snapshot, asserted that the final `RESTORE-END` marker survived, and measured through the GPUI callback after the rendered frame. Five measured runs reported 25.10 ms median and 29.13 ms p95. This is 53.8 times faster by median and passes the equal-or-faster restore gate.

Commands:

```bash
ALERA_FLAVOR=dev flutter test integration_test/terminal_restore_benchmark.dart -d linux
ALERA_GPUI_BENCH_MODE=restore experiments/alera-gpui/target/release/terminal_performance
```

## Input Encoding

The reproducible Flutter microbenchmark exercises `Terminal.textInput` and its output callback in batches. GPUI measures `TerminalEmulator::encode_key` for the corresponding text key.

```bash
flutter test experiments/alera-gpui/tool/flutter_terminal_input_benchmark.dart
ALERA_GPUI_BENCH_MODE=stream experiments/alera-gpui/target/release/terminal_performance
```

Flutter reported 0.010 µs p95 and GPUI reported between 0.028 and 0.078 µs p95 across the final stream and restore processes. GPUI's extra allocation is measurable but remains below one microsecond and does not introduce a scheduler or frame. This is effectively neutral for perceived input latency, but it is not an end-to-end key-to-PTY-echo benchmark. A production gate should measure physical key dispatch through PTY echo on both clients.

## Interpretation

The decisive gain comes from frame production and Linux composition, not only VT parsing. GPUI can remain idle when state is unchanged and render at the chosen terminal cadence without Flutter's extra binding frames and GTK3 software readback path. The result supports proceeding with a migration, provided terminal correctness and product UX are treated as separate release gates.

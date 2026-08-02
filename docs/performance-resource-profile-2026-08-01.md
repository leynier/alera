# Desktop Resource Optimization - 2026-08-01

## Goal

Reduce CPU and RAM retained by the Flutter desktop client without changing terminal protocol compatibility, PTY lifetime, interactive echo latency, or the three-second default terminal restoration target.

## Scope

This profile covers the Flutter desktop process. The runtime host and mobile client have separate optimization workspaces, so no Rust sampler, sidecar lifecycle, protocol, or mobile behavior changed here.

## Live Diagnosis

The installed desktop app was sampled on Linux while a visible agent terminal streamed output. The process held about 782 MiB RSS and used 120-139% aggregate CPU during the sampled intervals. Per-thread `pidstat` attribution placed about 51% of one core on the GTK platform thread and 32% on `io.flutter.raster`; the runtime host was about 3.4%. Repository source-control watchers added transient work while the active agents edited their checkouts, but terminal-driven frames were the dominant stable cost.

This matches the existing Linux profile: GTK3 reads the rendered surface back and composites it in software, so reducing frame count has more leverage than micro-optimizing the terminal painter.

The memory audit found two gaps in the existing terminal budget. It estimated each line from the current column count even though xterm rounds its typed-data capacity up and retains that allocation after a viewport shrink, and every terminal in the active workspace was exempt even when its tab was off screen.

## Design

- Keep the first output after quiet eligible for the next frame, preserving shell echo latency.
- Pace back-to-back output at a 50 ms floor, or 20 Hz, after existing measurements showed lower frame count tracks lower CPU on Linux.
- Treat the app lifecycle as an output-visibility gate. When the desktop window is hidden, pause host delivery and frame scheduling; when it returns, resume through the existing per-client delivery cursor.
- Keep mounted panes pinned so lifecycle changes cannot evict a handle still owned by the widget tree.
- Make off-screen tabs in the active workspace eligible for least-recently-visible eviction and measure their allocated xterm cell buffers directly.

## CPU Measurement

The command was `ALERA_FLAVOR=dev flutter test integration_test/terminal_flush_cadence_benchmark.dart -d linux`. Five before and five after samples ran on the same machine, Flutter 3.44.8, display session, debug device build, and concurrent desktop workload.

| Metric | Before | After | Change |
| --- | ---: | ---: | ---: |
| Median terminal flushes per second | 29.0 | 19.5 | -32.8% |
| Median process CPU, one-core scale | 89.9% | 76.7% | -14.7% |
| Median writes accepted per second | 90 | 92 | +2.2% |

The input rate stayed comparable while rendered terminal updates fell by roughly one third. CPU samples were noisier because the installed Alera process and multiple agents remained active, so the median is the decision metric.

## Restoration Guardrail

`ALERA_FLAVOR=dev flutter test integration_test/terminal_restore_benchmark.dart -d linux` replayed the default 2.56 MB snapshot plus a 1 MiB live backlog. All five samples stayed within target: 2,074.59 ms median, 2,369.25 ms p95 and maximum, 6.58 ms MAD, and 40 flushes per restore.

## Memory Contract

The new accounting sums each `BufferLine.data.lengthInBytes`, so a 120-column line is budgeted at its real 128-cell allocation and remains budgeted at that size after shrinking to 80 columns. Runtime tests verify that off-screen terminals in the active workspace are evicted when the configured ceiling is exceeded, panes currently on screen stay pinned, and eviction detaches from the sidecar without terminating the running agent.

The retained-RAM reduction depends on how many populated off-screen terminal tabs a user has and their widest recent viewport, so no synthetic RSS percentage is presented as universal. The important invariant is that those buffers can no longer bypass or under-report against the configured ceiling.

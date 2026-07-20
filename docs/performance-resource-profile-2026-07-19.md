# Desktop Resource Profile - 2026-07-19

## Goal

Measure Alera Desktop under common workbench, terminal, quota, and real-agent workloads; separate Flutter and development tooling from the shipped app and provider processes; remove demonstrated bottlenecks; and repeat the quota workload in a macOS Profile build.

## Test Setup

- Platform: macOS, Alera Dev, Profile build for the release-like comparison.
- UI driver: Codex Computer Use with the window maximized.
- Sampling: `ps` every 250 ms through `tool/performance/alera_resource_profile.dart`.
- Quota providers: Claude Default, CCS `leynier41`, CCS `leynierdev`, Codex, Kimi, Grok Build, Antigravity, MiniMax, and Z.ai.
- Common workloads: idle, project and workspace navigation, terminal output burst, quota refresh, and two concurrent real Codex agents.
- Process groups: app, runtime host, Flutter tooling, build runner, terminal descendants, agent and provider CLIs, and tracked total.

Raw local reports are under `.dart_tool/performance/` and stay out of version control because they contain machine-specific process measurements.

## Resource Attribution

Debug idle after normal work used a median 279.67 MiB in the Flutter app, 74.86 MiB in Flutter tooling, 25.28 MiB in the build runner group, and 404.01 MiB tracked total. The repository-scoped build runner rose to about 981 MiB while regenerating code. These are development and JIT costs, not shipped application memory.

A 20,000-line terminal burst kept the app at 1.4% median CPU, 6.1% p95 CPU, and 280.52 MiB median RSS in Debug. The runtime host remained near idle, so terminal rendering was not the dominant bottleneck.

Two concurrent real Codex agents produced up to 965.72 MiB of agent RSS and 367.6% aggregate agent CPU while the app stayed at 0.4% median CPU and 6.1% maximum CPU. The heavy cost belonged to provider CLIs, not Alera or Flutter JIT.

## Quota Refresh Before And After

The before report is `.dart_tool/performance/resources_profile_quota_clean_before.json` with 90 samples. The after report is `.dart_tool/performance/resources_profile_quota_with_ccs_after_final.json` with 140 samples and the requested Claude Default plus both CCS profiles visible in the status bar.

| Metric | Before | After | Change |
| --- | ---: | ---: | ---: |
| Tracked total peak RSS | 1509.69 MiB | 739.11 MiB | -51.0% |
| Agent and provider peak RSS | 1377.97 MiB | 457.26 MiB | -66.8% |
| Tracked total p95 CPU | 514.0% | 44.3% | -91.4% |
| Tracked total peak CPU | 564.7% | 178.0% | -68.5% |
| Maximum tracked process count | 34 | 13 | -61.8% |
| Runtime host peak CPU | 12.1% | 7.2% | -40.5% |

The after workload is broader because it includes both CCS profiles in addition to Default. The after app window was also maximized on a larger display area, so app-only RSS is not compared directly. Despite that conservative difference, total peak RSS was cut by more than half.

Before the change, the Claude TUI took 14.03 seconds and peaked at 462.75 MiB for `leynier41`; `leynierdev` took 27.98 seconds, peaked at 550.52 MiB, and failed to parse. The direct OAuth path queried Default and both CCS scopes in 2.30 seconds with a 23.17 MiB peak; both CCS profiles succeeded and Default returned signed out without launching Claude.

## Implemented Changes

- Read Claude OAuth credentials from the profile-scoped macOS Keychain service, with the legacy Default service and credential file as safe fallbacks.
- Query the official Claude OAuth usage endpoint directly and isolate CCS profiles from Default credentials.
- Reserve Claude CLI and PTY work for explicit manual fallback or stale-token repair; unsigned accounts fail without spawning Claude.
- Reuse the runtime-host cache and extend routine refreshes from 5 to 15 minutes; only the refresh button bypasses the cache.
- Limit concurrent quota CLIs to two processes.
- Kill and wait for timed-out Codex and PTY children so provider refreshes do not accumulate zombies.
- Add a repeatable macOS CPU and RSS profiler plus `make app-profile` and `make perf-macos-resources` workflows.

These changes follow Orca's high-value quota pattern: direct provider APIs and scoped credentials for the normal path, bounded and explicit CLI recovery, coordinated caching, and no CLI launch when authentication is absent.

## Validation

- Codex Computer Use: maximized window, configured and displayed Claude Default, `leynier41`, and `leynierdev`, refreshed all quotas, and safely removed the temporary profiling project metadata.
- Runtime process check after refresh: 0 direct children and 0 zombie children.
- `flutter analyze`: no issues.
- `flutter test`: 1696 passed, 1 skipped, 0 failed.
- `make rust-test`: formatting, Clippy with warnings denied, and all workspace tests passed.
- `PERF_SCENARIO=smoke PERF_DURATION_SECONDS=5 PERF_APP_PID=<pid> make perf-macos-resources`: passed.
- `git diff --check`: passed.

## Remaining Interpretation

The largest remaining quota peak is Antigravity's interactive `agy` process at roughly 457 MiB. Alera already bounds that work and caches its result, but a further large reduction requires an authenticated non-interactive Antigravity usage API or a lighter official command. Flutter Debug and build-runner measurements should continue to be reported separately from Profile app measurements.

# Agent Chat Rendering Measurement

Run `integration_test/agent_chat_render_benchmark.dart` explicitly on a native device from an isolated QA checkout after live UI QA finishes. It is intentionally outside `*_test.dart` CI discovery. Native builds may still run the repository's normal build hooks; the benchmark itself never initializes Rust, providers or the application runtime, and never reads provider credentials. Its opt-in VM evidence helper records only the already-running loopback VM service in a private file; the separate driver attaches to that service. The separate host driver uses the local VM service to retrieve results.

Use the opt-in service evidence recipe below when Sky cannot inject a launch environment or retain launch stdout; the later engine-switch recipe requires environment injection. Both preserve the user's foreground through root's configured background launcher. Use Flutter 3.47.2 / Dart 3.13.2. The SDK's `flutter test` command uses debug mode and does not accept `--profile`; tool-launched Mac apps also take the foreground through `open`. Keep device, SDK, build mode, window size, display configuration and power mode fixed between comparisons. Capture at least five runs for optimization decisions. The JSON data is available under the integration binding's `agent_chat_render_benchmark` report key and is captured by the host driver below, even when launch-time stdout was not retained. If stdout is available, preserve its `AGENT_CHAT_BENCHMARK_JSON` line too. Record the checkout revision and SDK version alongside the data.

1. Stream a growing assistant message for eight seconds with a real 50 ms pause between canonical updates, after warm-up. The producer does not catch up with bursts if rendering falls behind; elapsed time and update counts expose effective delivery cadence.
2. Repeat with 160 completed user/assistant turns retained in the shared projection and a lazy list while the newest assistant output grows. Payloads include paragraphs, inline styles, lists, tables and code fences split across updates.
3. Pause output for eight seconds with the message still in progress, keeping the production Writing shimmer active. Then complete the message and observe eight seconds of idle cadence with the same history retained.

Each report includes elapsed time, update and character counts, logical viewport dimensions, framework and timed frame counts, frames per second, and FrameTiming build/raster p50/p95. Warm-up, completion and the two-second timing-report drain are outside measured windows. FrameTiming samples are matched to engine frame numbers observed during the framework draw callback to exclude neighboring windows even when the engine batches reports. A completed idle window may produce zero frames, in which case percentiles are null / `n/a`; no frames are forced to manufacture idle samples. Assertions check that streaming produced native frames, every canonical item survives projection, the full latest Markdown reaches the production widget, and the final marker is parsed and visible. There are no performance pass thresholds.

The provider-free boundary is `AgentChatTimelineProjection`, completed `AgentChatTimelineEntryView` rows and the production `AgentChatUserMessageView` / `AgentChatAssistantMessageView`, under the actual Alera theme, tokens, selection area and shimmer scope. Stable completed sections reuse widgets. The live turn uses those message rows directly because its production header and scrolling coordinator read Riverpod. A reversed lazy list keeps the output tail visible. This measures projection plus message rendering and shimmer cadence; it does not measure provider transport, the live header, the production scroll coordinator, full workbench CPU or recipient delivery. Synthetic fixtures contain no remote images or active links.

## Observed macOS Baseline

One successful profile run on the MacBook Air used Flutter 3.47.2 / Dart 3.13.2, an 800 by 600 logical viewport and device pixel ratio 2. The source was the working implementation based on `2efa844892f9831a00096bd8215ae702ad85333b`, including the scheduling correction below. The existing-app driver exited zero, returned all four scenarios and passed rendering and teardown assertions. This is a baseline, not a five-run optimization comparison or a full-workbench performance guarantee.

| Scenario | Updates | Measured Frames | Frames / Second | Build p95 | Raster p95 |
| --- | --- | --- | --- | --- | --- |
| Streaming | 154 | 342 | 42.72 | 22.84 ms | 0.83 ms |
| 160 Turns And Streaming | 154 | 335 | 41.61 | 22.71 ms | 0.67 ms |
| 160 Turns, Writing Idle | 0 | 160 | 20.00 | 0.68 ms | 3.26 ms |
| 160 Turns, Completed Idle | 0 | 0 | 0.00 | n/a | n/a |

The completed idle window produced no frames. Streaming build p95 exceeded a 16.7 ms display interval, so the result does not establish smooth rendering for every update. Any optimization decision requires repeated samples under the same conditions and investigation of the build cost. Earlier null reports, timestamp-filtered samples and failed fully-live runs are excluded. The private VM rendezvous and background attachment worked without disabling service authentication. The benchmark process was closed after capture.

## Test Harness Scheduling And Accessibility Correction

The first native profile report contained all four scenarios but failed WidgetTester's teardown with `A SemanticsHandle was active at the end of the test.` Platform accessibility enabled semantics during the test. In pinned Flutter 3.47.2 (framework revision `d3b14c876900e553bc736ca19295fc09e3853e8e`), `SemanticsBinding._handleSemanticsEnabledChanged` retains exactly one platform-owned handle while `platformDispatcher.semanticsEnabled` is true. WidgetTester records its initial handle count before the test and treats the later platform handle as a leak. The test-only `AgentChatBenchmarkBinding.debugOutstandingSemanticsHandles` subtracts exactly that one handle while platform semantics is enabled. App and tester handles remain counted; the pipeline owner's separate count and all other WidgetTester setup, unmounting, teardown and rendering assertions remain unchanged. Accessibility stays enabled and its semantics tree is still rendered.

That earlier run also used `.fullyLive`. The pinned `LiveTestWidgetsFlutterBinding.handleDrawFrame` unconditionally calls `platformDispatcher.scheduleFrame()` after a non-pumped frame unless the policy is `.benchmark`. Consequently `.fullyLive` creates a display-rate idle loop even after the message and animations finish; its idle frame counts cannot establish product idle cadence. Stock `.benchmark` also suppresses framework `scheduleFrame` and `scheduleForcedFrame`, so it would prevent natural widget and animation updates and stall ordinary test pumps.

The new binding keeps `.benchmark` for frame handling and temporarily selects `.fullyLive` only during the synchronous superclass calls to `scheduleFrame` and `scheduleForcedFrame`, restoring `.benchmark` in `finally` before an engine frame can arrive. This preserves the scheduler's lifecycle gate, duplicate-request coalescing, native frame callbacks and normal harness pumps while removing only the live binding's unconditional next-frame request. No manual per-vsync pumping, timer-driven frame requests or artificial samples are added to the benchmark. A genuinely active Writing shimmer can still schedule animation frames; completed idle can naturally produce zero frames. `pumpAndSettle` remains unsupported under benchmark policy and is not used.

Focused SDK-only tests cover platform AX toggles with an additional app handle, WidgetTester verification while AX remains enabled, natural notifier-driven rendering, continuing ticker animation, frame-free idle and forced-frame delegation. The explicit expected-failure probe `test/fixtures/agent_chat_benchmark_semantics_leak.dart` must fail with the semantics-handle invariant when an app handle is intentionally leaked. These tests can run in a temporary package containing only the binding, these tests and Flutter SDK test dependencies to avoid this repository's native build hooks. Run `flutter test --no-pub --no-test-assets --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false test/unit/agent_chat_benchmark_binding_test.dart` in that package, then invoke `test/fixtures/agent_chat_benchmark_semantics_leak.dart` with the same flags and require exit code 1 plus `WidgetTester._verifySemanticsHandlesWereDisposed` in its failure stack. They validate harness behavior on Linux's `flutter_tester`; the separate corrected native result is recorded above. Retain the driver report guard and reject failed runs even if their JSON contains all scenarios. Recheck these SDK implementation details and rerun the focused tests before changing the pinned Flutter version.

## Background macOS Profile Capture Without Launch Environment Injection

This test-only alternative uses `await Service.getInfo()` from `dart:developer` to discover the profile VM's existing HTTP service. Dart 3.13.2's `bin/cache/dart-sdk/lib/developer/service.dart` returns `ServiceProtocolInfo.serverUri`, which is nullable while the service is unavailable; see also the [SDK API](https://api.dart.dev/dart-developer/Service/getInfo.html). The helper neither starts nor reconfigures that service. Without `ALERA_AGENT_CHAT_BENCHMARK_SERVICE_INFO`, it returns immediately without inspecting the service or filesystem. This alternative passed local Linux unit checks and the background Mac launch and attachment used for the baseline above.

1. Root precreates a fresh private evidence directory on the Mac **before the build**, then passes the exact absolute filename through the build define. Use a canonical path without symlink components, a directory with mode `0700`, and an absent output file. Keep this directory for the result and driver log. Use the configured pinned Mac Flutter executable and a fresh benchmark product identity in an isolated QA checkout.

```bash
set +x
umask 077
bench_evidence=$(mktemp -d /private/tmp/alera-chat-benchmark.XXXXXX)
bench_service_info="$bench_evidence/vm-service.json"
export FLUTTER_TEST_OUTPUTS_DIR="$bench_evidence"
bench_flutter=/absolute/path/to/pinned/flutter/bin/flutter
FLUTTER_XCODE_ALERA_PRODUCT_NAME='Alera QA Bench' \
FLUTTER_XCODE_ALERA_BUNDLE_ID='dev.leynier.alera.agentqa.benchmark.20261013' \
"$bench_flutter" build macos --profile \
  --target=integration_test/agent_chat_render_benchmark.dart \
  --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false \
  --dart-define="ALERA_AGENT_CHAT_BENCHMARK_SERVICE_INFO=$bench_service_info"
```

2. Root checks the built `build/macos/Build/Products/Profile/Alera QA Bench.app` identity, executable and benchmark target, then opens that exact bundle with its already configured Sky background call. No launch environment, stdout capture or engine flags are required. Do not use `start-paused`: main must run to publish evidence, and the existing integration test auto-runs after publication. Retain Sky's actual app PID as `bench_pid` and verify that it belongs to this bundle. The helper waits at most ten seconds for readiness, accepts only a numeric loopback HTTP host, a valid explicit port and a nonempty authentication path, then exclusively creates JSON containing only this process's `pid` and `uri`. It applies `0600` through the existing POSIX chmod syscall boundary before writing content. It rejects malformed paths, existing files, symlinked parents and parents whose mode is not `0700`; it never prints the URI or spawns a process.

3. Discover the complete file with a bounded wait from the same shell, matching `bench_pid` to Sky's launch result. The command captures the URI into a shell variable without displaying it; keep tracing disabled and do not echo the variable. The private output may briefly be empty during creation. File/directory permissions, ownership, PID and URI checks must succeed before attachment.

```bash
bench_vm_uri=$(python3 - "$bench_service_info" "$bench_pid" <<'PY'
import json
import os
import re
import stat
import sys
import time
from urllib.parse import urlsplit

path = sys.argv[1]
expected_pid = int(sys.argv[2])
parent = os.path.dirname(path)
if (expected_pid <= 0 or not os.path.isabs(path)
        or os.path.realpath(parent) != parent):
    raise SystemExit("Invalid benchmark evidence path or launch PID")
directory = os.lstat(parent)
if (not stat.S_ISDIR(directory.st_mode)
        or stat.S_IMODE(directory.st_mode) != 0o700
        or directory.st_uid != os.getuid()):
    raise SystemExit("Benchmark evidence directory is not private")

deadline = time.monotonic() + 30
while time.monotonic() < deadline:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, encoding="utf-8") as stream:
            status = os.fstat(stream.fileno())
            if not stat.S_ISREG(status.st_mode) or status.st_size > 4096:
                raise SystemExit("Invalid benchmark service evidence file")
            if status.st_size == 0:
                time.sleep(0.1)
                continue
            if (stat.S_IMODE(status.st_mode) != 0o600
                    or status.st_uid != os.getuid()):
                raise SystemExit("Benchmark service evidence is not private")
            data = json.load(stream)
        if (set(data) != {"pid", "uri"} or type(data["pid"]) is not int
                or data["pid"] != expected_pid or not isinstance(data["uri"], str)):
            raise SystemExit("Benchmark service evidence does not match launch")
        parsed = urlsplit(data["uri"])
        if (parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "::1"}
                or not parsed.port or parsed.username is not None
                or parsed.password is not None or parsed.query or parsed.fragment
                or not re.fullmatch(r"/[A-Za-z0-9_-]+={0,2}/", parsed.path)):
            raise SystemExit("Invalid authenticated loopback service URI")
        os.kill(expected_pid, 0)
        sys.stdout.write(data["uri"])
        break
    except (FileNotFoundError, json.JSONDecodeError):
        time.sleep(0.1)
    except (OSError, ValueError, TypeError):
        raise SystemExit("Could not validate benchmark service evidence") from None
else:
    raise SystemExit("No complete private VM service file within 30 seconds")
PY
) || exit 2
```

4. Attach promptly: the benchmark runs automatically, with all readiness and file I/O completed before any scenario begins. Existing-app attachment neither launches nor builds the bundle. The driver collects `reportData` even when launch stdout was unavailable. Keep the full driver log private because connection diagnostics can contain the authenticated URI.

```bash
"$bench_flutter" drive -d macos --profile --no-pub \
  --target=integration_test/agent_chat_render_benchmark.dart \
  --driver=test_driver/agent_chat_benchmark_driver.dart \
  --use-existing-app="$bench_vm_uri" \
  --no-dds --no-devtools --keep-app-running \
  >"$bench_evidence/driver.log" 2>&1
bench_driver_status=$?
unset bench_vm_uri
test "$bench_driver_status" -eq 0
test -s "$bench_evidence/agent_chat_render_benchmark.json"
```

Use the verification and cleanup rules at the end of the engine-switch recipe: check all four scenario reports, then close only the task's benchmark bundle. Keep its private evidence until review is complete. Every new launch requires a fresh absent output path; rebuild with a fresh evidence path rather than reusing or deleting earlier service evidence. Never disable VM service authentication or origin checks, change its bind address, or edit product startup for this discovery path.

## Background macOS Profile Capture With Launch Environment Injection

The following recipe is verified against the local Flutter 3.47.2 / Dart 3.13.2 SDK source, not a Mac execution. Build in a dedicated QA Bench checkout so the existing R2 QA app, its build tree and the user's foreground app remain available. Use the root agent's configured Mac Flutter executable for `bench_flutter`; the Linux verification path is `/home/leynier/.puro/envs/v3_47_2/flutter`.

1. Build the benchmark entrypoint only, with a distinct product identity. Flutter forwards `FLUTTER_XCODE_*` environment variables as command-line Xcode settings; the project's `AppInfo.xcconfig` derives its product name and bundle identifier from these Alera settings. Pick a fresh bundle identifier for this QA run. This build command does not launch the app.

```bash
bench_flutter=/absolute/path/to/pinned/flutter/bin/flutter
FLUTTER_XCODE_ALERA_PRODUCT_NAME='Alera QA Bench' \
FLUTTER_XCODE_ALERA_BUNDLE_ID='dev.leynier.alera.agentqa.benchmark.20261013' \
"$bench_flutter" build macos --profile \
  --target=integration_test/agent_chat_render_benchmark.dart \
  --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
```

The expected bundle is `build/macos/Build/Products/Profile/Alera QA Bench.app` in that checkout. Root must inspect the built bundle's actual identifier, executable and compiled target before launch; do not reuse the R2 QA bundle. Product settings and the target are build inputs, not benchmark source changes. Normal native build hooks may still compile native dependencies.

2. Create a fresh private evidence directory on the Mac, in the same shell that will run the host driver. `mktemp -d` creates the directory with restricted access; `umask` also restricts the driver log and result files. Do not reuse a service-info file from an earlier process.

```bash
umask 077
bench_evidence=$(mktemp -d /private/tmp/alera-chat-benchmark.XXXXXX)
export FLUTTER_TEST_OUTPUTS_DIR="$bench_evidence"
```

3. Through root's already configured Sky background launcher, launch that exact new QA Bench bundle with the following per-process environment. Substitute the fresh absolute evidence path into switch 6 before launch. These values are engine switches, not application arguments: the macOS embedder reads `FLUTTER_ENGINE_SWITCH_*`, prefixes `--` itself, and ignores this mechanism in release mode.

```text
FLUTTER_ENGINE_SWITCHES=6
FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling=true
FLUTTER_ENGINE_SWITCH_2=vm-service-host=127.0.0.1
FLUTTER_ENGINE_SWITCH_3=vm-service-port=0
FLUTTER_ENGINE_SWITCH_4=disable-vm-service-publication=true
FLUTTER_ENGINE_SWITCH_5=start-paused=true
FLUTTER_ENGINE_SWITCH_6=dart-flags=--write-service-info=/private/tmp/<fresh-evidence-dir>/vm-service.json
```

The parent must retain its already verified Sky call shape and background setting. The local Flutter SDK does not define `configuredSky`, so this document does not invent its argument or environment field names. Per-process environment injection is an essential launcher prerequisite; passing these as ordinary app arguments is not equivalent. If the configured launcher cannot inject the environment, this exact recipe is not ready to execute. No Sky calls or Mac processes were exercised while preparing this guidance.

The VM binds an automatically assigned loopback port and retains its authentication token and origin checks. The Dart VM flag `--write-service-info` is expressly allowed by the non-release engine and writes JSON with a `uri` property. The directory must already exist. Do not use `disable-service-auth-codes`, `disable-service-origin-check`, `0.0.0.0`, or a fixed shared port. Choose an evidence path without commas because the engine splits `dart-flags` on commas.

4. Wait for that new file with a bounded deadline, and validate its complete JSON and loopback URI before attaching. The example uses Python 3 on the Mac and never prints the URI to a tool result. It rejects a missing token, a non-loopback host and an invalid port. The private directory ties discovery to this launch; root should also match Sky's returned PID and bundle identity before attachment.

```bash
bench_vm_uri=$(python3 - "$bench_evidence/vm-service.json" <<'PY'
import json
import sys
import time
from urllib.parse import urlsplit

deadline = time.monotonic() + 30
while time.monotonic() < deadline:
    try:
        with open(sys.argv[1], encoding="utf-8") as stream:
            uri = json.load(stream)["uri"]
        parsed = urlsplit(uri)
        if (parsed.scheme != "http" or parsed.hostname != "127.0.0.1"
                or not parsed.port or not parsed.path.strip("/")):
            raise ValueError("Invalid private VM service URI")
        sys.stdout.write(uri)
        break
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        time.sleep(0.1)
else:
    raise SystemExit("No complete private VM service file within 30 seconds")
PY
) || exit 2
```

5. Attach from the same isolated checkout using the explicit host driver. `--use-existing-app` calls `reuseApplication` rather than `startApp`, so it does not reach `MacOSDevice.onAttached`, which otherwise runs `open` and foregrounds the bundle. Disable DDS and DevTools to keep the attachment minimal. The driver connection resumes the paused isolate; the compiled test main then auto-runs. The request-data callback waits for the test result and returns `reportData`; it does not start the benchmark or require a click.

```bash
"$bench_flutter" drive -d macos --profile --no-pub --no-dds --no-devtools \
  --target=integration_test/agent_chat_render_benchmark.dart \
  --driver=test_driver/agent_chat_benchmark_driver.dart \
  --use-existing-app="$bench_vm_uri" --keep-app-running \
  >"$bench_evidence/driver.log" 2>&1
bench_drive_status=$?
unset bench_vm_uri
```

The output is `$bench_evidence/agent_chat_render_benchmark.json`; its `agent_chat_render_benchmark` property contains the benchmark's reports. `driver.log` may contain the authenticated URI because FlutterDriver logs connection details, so keep the log, service JSON and any command metadata private. A JSON file alone does not imply success: check `bench_drive_status`, failure details and the expected report scenarios. The driver writes available data on failure, requires `FLUTTER_TEST_OUTPUTS_DIR`, and bounds connection plus result collection to three minutes. Its two-minute request timeout starts after connection. The SDK's `drive --timeout` is wired through its screenshot callback registration, so this recipe relies on the driver's watchdog instead of that flag. Tool startup before the driver process begins remains outside the watchdog.

6. Keep the owned benchmark app visible behind the user's foreground window, on screen and not minimized or hidden. A fully occluded or hidden macOS window may receive fewer or no frames, and the shimmer scope also reacts to lifecycle state; report that as an execution limitation, not a rendering result. Record the frontmost identity before and after Sky launch and VM attachment using root's existing read-only QA tools. Source inspection proves that this Flutter reuse path avoids `open`; it does not prove that Sky, AppKit or the native runner preserved focus on the actual Mac. The benchmark needs a native run to establish that. `--keep-app-running` leaves only this owned benchmark process for root to close through the existing background-safe cleanup after retrieving evidence. Repeat from a fresh process and evidence directory for each sample.

## Verified SDK Sources

Paths are relative to the pinned Flutter SDK root.

- `packages/flutter_test/lib/src/binding.dart`: `.benchmark` suppression in both scheduling methods, live begin/draw-frame policy gates, unconditional native scheduling after non-pumped draws and normal pump completion.
- `packages/flutter/lib/src/scheduler/binding.dart`: synchronous `scheduleFrame` / `scheduleForcedFrame` registration and native requests, duplicate-request coalescing and lifecycle handling.
- `packages/flutter/lib/src/semantics/binding.dart` and `packages/flutter_test/lib/src/widget_tester.dart`: exact platform-handle ownership and WidgetTester's baseline, test-owned semantics handle and end-of-test leak verification.
- `packages/flutter_test/lib/src/test_compat.dart`: the local declarer schedules and runs tests directly when no test runner declarer is in the zone. Compiled `main()` does not need a host start command once its isolate is resumed.
- `packages/integration_test/lib/integration_test.dart` and `packages/integration_test/lib/src/_callback_io.dart`: register `ext.flutter.driver`; `request_data` awaits `allTestsPassed` and returns the binding's result data. Native macOS completion reporting is a no-op in `integration_test_macos`, and the build define disables that reporting path explicitly.
- `packages/flutter_tools/lib/src/commands/build_macos.dart`, `packages/flutter_tools/lib/src/macos/build_macos.dart` and `packages/flutter_tools/lib/src/ios/xcodeproj.dart`: build-target propagation and `FLUTTER_XCODE_*` conversion to Xcode build settings.
- `packages/flutter_tools/lib/src/commands/drive.dart` and `packages/flutter_tools/lib/src/drive/drive_service.dart`: existing-app reuse, host `VM_SERVICE_URL`, app retention and the screenshot-dependent timeout registration. Reuse does not build, install or launch the app; `--no-pub` assumes dependencies are already resolved in the isolated checkout.
- `packages/flutter_tools/lib/src/macos/macos_device.dart`: `onAttached` foregrounds a tool-launched app with `open`.
- `packages/flutter_driver/lib/src/driver/vmservice_driver.dart`, `packages/flutter_driver/lib/src/driver/driver.dart` and `packages/flutter_driver/lib/src/driver/common.dart`: resume on paused startup, connection behavior and `FLUTTER_TEST_OUTPUTS_DIR`.
- `packages/integration_test/lib/integration_test_driver.dart`: result collection and the response callback's JSON filename/directory options.
- `engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngine.mm` and `engine/src/flutter/shell/platform/common/engine_switches.cc`: desktop engine environment switch loading in debug/profile.
- `engine/src/flutter/shell/common/switch_defs.h`, `engine/src/flutter/shell/common/switches.cc` and `engine/src/flutter/runtime/dart_vm.cc`: VM host/port, startup pause, publication controls and the non-release `--write-service-info` allowlist.
- `bin/cache/pkg/sky_engine/lib/_internal/vm/bin/vmservice_io.dart` and `bin/cache/pkg/sky_engine/lib/_internal/vm/bin/vmservice_server.dart`: authenticated service-info JSON output. This is different from tool flag `--vmservice-out-file`, whose resident runner writes a plain WebSocket URI and is not a stand-alone engine switch or a reuse-path discovery mechanism.

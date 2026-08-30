# Relay Validation Record

This worktree implements negotiated renewal, per-peer transport isolation, byte budgets, cancellation and connection diagnostics. No production service or installed application was changed.

## Automated Validation

- Mobile: 594 tests passed; three cross-language cases are intentionally skipped by the ordinary Flutter suite and run separately through workerd. Flutter analysis passed. Generated providers are included with their sources.
- Desktop: the full suite passed with 3,352 tests and one intentionally skipped case, including the selected mobile access/model/widget regressions. Flutter analysis passed.
- Edge: 37 tests and TypeScript checking passed, including renewal, replacement fencing, reconstruction from attachments, invalid expiry, temporary JWKS failure and legacy/disabled negotiation.
- Cloud: Clippy with warnings denied, formatting and 19 unit tests passed. All three PostgreSQL contracts also passed against an isolated, temporary local PostgreSQL 17 container.
- Rust: the final workspace suite passed with 1,860 tests and four intentionally ignored cases when run serially; formatting and Clippy with warnings denied passed. Parallel runs exposed unrelated terminal-test timing failures: `tab_removal_bypasses_its_active_pointer_and_cleans_only_affected_owners` passed alone, and the previously documented `cancelling_active_worker_interrupts_before_idle_banner_delivery` passed in both serial workspace runs. Neither test was changed.

## Measurements And Limits

The final 20-second Dart/Rust/workerd run completed with eight clients, 504 matching responses, one runtime renewal and eight mobile renewals. It explicitly evicted the Durable Object twice with WebSocket hibernation, including across the first renewal. There were exactly eight runtime peer connections: no reconnection was needed. Connection p50/p95 were 70.9/118.2 ms and response p50/p95 were 51.7/111.5 ms. Runtime sampled peak RSS was 59.9 MiB and Flutter fixture peak RSS was 266.6 MiB.

Both adversarial cross-language cases passed. Eight connections included an unconfirmed handshake, a client that stopped reading and six active clients, one sending 65 KB payloads. The handshake expired after ten seconds, its admission slot became reusable and the other clients kept responding. A separate case performed twelve replacements while requests were in flight and a second client remained connected. Rust unit tests verify shared byte budgets and lease release, round-robin fragment scheduling and socket-write acknowledgement before restart. These tests do not claim that the remote application received a restart response.

These are local debug-fixture measurements under concurrent development load, not production latency or a comparison against the previous release. Connection percentiles use only eight initial connections. Queue budgets cover application-owned reservations, not total process RSS, operating-system socket buffers or Cloudflare's internal buffers.

The fixture starts with a 35-second grant so the first renewal happens after five seconds, then issues normal 120-second grants with renewal 30 seconds before expiry. Production grant lifetime remains 120 seconds. Run the fixtures from `edge/` using `bun run test:integration`, `bun run test:adversarial` and `bun run test:soak`; `FLUTTER_BIN` can select the Flutter executable.

The one-hour run completed 90,424 matching responses on eight clients, with 40 runtime renewals and 320 mobile renewals and no disconnected client. Connection p50/p95 were 30.3/82.7 ms and response p50/p95 were 50.1/142.3 ms. Rust peak RSS was 58.3 MiB, read from the process high-water mark at one-second intervals; this version of the fixture did not capture Flutter peak RSS.

The one-hour run uses the renewal implementation captured when that run started. Additional error-path hardening was reviewed and tested separately afterward; the final cross-language short/adversarial runs validate those later changes. The final actor-handler extraction only relocates the dispatch code and is covered by the Rust workspace suite. The fixture uses real cryptography and WebSocket transports but an echo actor instead of the full workbench. It cannot certify UI draft preservation, duplicate side effects in real commands, operating-system suspension or radio handoff.

The scoped file-size ratchet passed after extracting relay handlers from `server.rs`, but PR job `99205679849` exposed that CI requires the repository-wide scan too. That scan rejected two files already above 500 lines in the starting revision. The follow-up fix separates terminal input methods from `terminal_session_controller.dart` and shares the lifecycle fixture between connection and terminal tests. It preserves the test cases and the original size limit; no baseline exceptions were added.

After this follow-up, the exact global file-size check, desktop formatting and analysis, mobile analysis and all 594 ordinary mobile tests passed locally. Riverpod was regenerated once for the extraction. The controller now has 456 lines and the connection test file has 495 lines. The failed remote job has not been rerun with these uncommitted changes.

No Android device was attached according to `adb devices -l`. iOS device tooling is unavailable on this Linux host. Real Android/iOS tests remain a release gate: cold start, rapid foreground/background changes, file picker, Wi-Fi/cellular transition, suspension beyond 120 seconds and runtime restart. Use the same devices, builds, payloads and network shaping for a before/after p50/p95 and peak-memory comparison. No such baseline comparison has been claimed here.

## Staged Release Gate

Deploy edge compatibility first with renewal disabled if a canary is needed, then ship the runtime, then mobile. Enable negotiated renewal only for the tested cohort. Observe normalized disconnect causes, connection/response percentiles, queue saturation, renewal success and RSS; do not record grants, keys or terminal content. Require physical-device acceptance before broad mobile rollout. Roll back renewal using the independent flags documented in `edge/readme.md`; keep Remote Access itself enabled unless the whole relay must be disabled.

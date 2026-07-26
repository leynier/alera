# AGENTS

## Scope

This file applies under `mobile/`. The root `AGENTS.md` also applies; this file only adds mobile-specific rules.

## Package Layout

- The mobile companion app is a separate Flutter package (`alera_mobile`) so mobile plugins and manifests never leak into the desktop package at the repo root.
- Source follows the desktop feature architecture: `lib/src/app/` (app shell and theme), `lib/src/core/` (protocol constants and payload parsing), `lib/src/design_system/` (presentational shared widgets with `@AleraPreview` previews), and `lib/src/features/<feature>/{domain,application,infra,presentation}`.
- Mobile UI values MUST come from the mobile `AleraTokens` (`lib/src/app/theme/alera_tokens.dart`) and `ThemeData`. The app is dark-only, Inter for general text and JetBrains Mono for monospaced text, matching the desktop rules.

## State Management

- Riverpod with `riverpod_generator` codegen is mandatory, same as the desktop app. No hand-written provider declarations and no new `StatefulWidget`-plus-`setState` state that belongs in a controller.
- The one-shot build_runner convention from the root `AGENTS.md` applies scoped to this package: after finishing a planned batch of edits that touches generated surfaces, run `flutter pub run build_runner build -d` once from `mobile/`, before formatting, analysis, and tests. Do not run a watcher.

## Testing

- Run `flutter test` and `flutter analyze` from `mobile/`.
- Unit tests override `hostRepositoryProvider` with `MemoryHostRepository` from `test/support/memory_host_repository.dart`.
- Client and connection tests use a real loopback `HttpServer` WebSocket harness; see `test/mobile_runtime_client_test.dart` and `test/host_connection_controller_test.dart`.

## Protocol

- The runtime gateway protocol version is `aleraMobileProtocolVersion` in `lib/src/core/mobile_protocol.dart`. The runtime enforces strict equality during `mobile.hello`, so never bump it for additive changes; feature-detect through the `runtimeCapabilities` array returned by the handshake instead.
- Terminal output may arrive as a binary WebSocket message (`[u16be idLength][sessionId][raw bytes]`) instead of base64 inside JSON. The app asks for it with `binaryFrames: true` in `mobile.hello` and the runtime answers with what it granted; feature-detect through that response and `runtimeCapabilities`, never through `aleraMobileProtocolVersion`. The WebSocket already delimits messages, so there is no length-prefixed framing here, unlike the desktop socket.
- Requests the gateway accepts from mobile clients are allowlisted in `rust/alera-cli/src/terminal_host/server/mobile_terminal_requests.rs` (`mobile_request_allowed`). Adding a new request type to the mobile app requires allowlisting it there first.
- What `mobile.hello` advertises lives in `MOBILE_HELLO_CAPABILITIES` (`rust/alera-cli/src/terminal_host/server/requests.rs`), which is a different list from the one `status.get` returns. A capability the app feature-detects MUST be in the hello list: an omission is invisible, leaves every phone permanently on the older code path, and has no version to blame because the runtime requires an exact `aleraMobileProtocolVersion` match.
- A composed prompt is sent with `write` carrying `bracketedPaste` and `deferredEnter`, negotiated through `terminalDeferredInputV1`. The host then writes the submit CR as its own PTY write half a second later, because an agent TUI runs paste heuristics over an input burst and reads a CR arriving inside that burst as a literal newline rather than a submit. Bracketing is only for text with newlines or other control characters: pasting a short command makes agent TUIs collapse it into a placeholder, and a program that has not enabled DECSET 2004 leaks the markers as literal text. Raw keys (accessory bar, direct mode) never set either flag. A host without the capability falls back to the single `text + "\r"` write.
- The app MUST answer `outputResyncRequired` with `setOutputPaused {paused: false}`, once per session at a time. The host's per-client terminal queue is bounded, one frame it cannot accept parks the client in the session's paused set, and only this resume or a fresh attach clears it, so ignoring the event leaves the terminal frozen on old content until the user leaves the screen and comes back. The host re-arms the ask every few milliseconds, which is why the answer is idempotent. A `delta: false` answer replaces the emulator contents; `delta: true` needs no local action because the host already pushed the missed bytes down the terminal lane.
- The mobile gateway's terminal lane is deeper than the desktop socket's (`MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY`), because a WAN send can stall for hundreds of milliseconds where the local socket the desktop value was tuned for does not.

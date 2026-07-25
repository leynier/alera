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
- Requests the gateway accepts from mobile clients are allowlisted in `rust/alera-cli/src/terminal_host/server/requests.rs` (`mobile_request_allowed`). Adding a new request type to the mobile app requires allowlisting it there first.

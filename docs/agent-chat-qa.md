# Agent chat QA

## Scope

This report records the 2026-10-13 QA round on macOS. The isolated `Alera Agent QA` app uses bundle ID `dev.leynier.alera.agentqa.20261013`, separate runtime data and two fixture projects. Personal app data, provider accounts and the runtime database were preserved. Provider calls below used the existing Mac accounts; mock tests are listed separately.

## Observed runtime results

| Case | Result | Evidence |
| --- | --- | --- |
| Codex text chat | Passed | Native completed turn, one persisted user message and the expected assistant marker. |
| Queue and idempotency | Passed | Two completed turns, one user item per message, original receipt replay and `request_conflict` for a changed payload. |
| Archive and reopen | Passed | Same transcript and turns, new tab for the reopened chat. |
| Cross-project delegation | Passed | Child ran in a different project's existing workspace, returned its marker and was not duplicated by retries. |
| Injected MCP | Passed | A completed native `alera.chat_capabilities` tool item was persisted. Native discovery was not exposed as a separate tools/list item. |
| Interruption | Passed | Observed native output before interruption, exact target turn became interrupted, then the chat became ready with no active work. |
| Codex to Grok handoff | Passed | Same chat/tab, generation increment, preserved history, and Grok recalled a public fixture phrase omitted from its new prompt. |
| Recovery after host restart | Passed | The table and transcript survived; Resume Session cleared recovery without an action error; the host reported ready. |
| Configure/recover wire replies | Passed | Both returned `{snapshot}` with the committed receipt cursor; replay retained the original snapshot after later changes. |
| OpenCode 1.18.16 | Passed | Real inference returned the marker and completed after native-ID and stream-mapping repairs. |
| Paired mobile client/gateway | Passed | Production client pairing, capability/catalog/snapshot parsing, rename event, cursor/reducer parity and title restoration. Temporary pairing credentials/device were removed. |

## Observed desktop UI

Creating a chat, typing a prompt and sending with Return produced a visible Codex reply and markdown table. Recovery retained that table and cleared the restart notice. A stopped empty chat now describes recovery instead of inviting a send, and a narrow composer separates its scrolling settings from the fixed mic/send controls.

The user confirmed Cmd+Shift+T opens New Agent Chat with the composer focused; a fresh native snapshot also captured that dialog. Synthetic Computer Use attempts for both Cmd+Shift+T and Cmd+Shift+P produced no action. This does not establish an application shortcut defect. The reusable macro supports a guarded, already-open QA dialog and checks the exact composer text and unchanged sidebar before attempting Return.

The first complete macro attempt safely stopped after creating an empty chat because the native accessibility snapshot omitted focus metadata. It typed nothing and sent nothing; that empty fixture was archived. Missing/generic focus metadata is now supported while explicit wrong-field focus and misdirected typing still stop the flow.

The next native macro created one chat, typed once and pressed Return once. The screenshot showed the expected Codex reply, and independent storage inspection confirmed exactly one user message and one completed turn. Its original report timed out because accessibility merged the user prompt and reply into one row. That report is preserved. The repaired pure observer recognized the same reply in two fresh native snapshots 1.1 seconds apart, with no UI actions or additional sends. It requires a distinct reply suffix after the exact prompt and rejects prompt-only markers.

## Repairs and regression coverage

- Chat-store writes acquire the SQLite writer lock before reading. Five deterministic concurrent-write cases and two rollback cases cover the previously observed `SQLITE_BUSY_SNAPSHOT`; the complete core suite passed 857 tests.
- Configure/recover command replies have one snapshot envelope and the final receipt cursor. Seven real socket regressions cover replay, conflict, restart, native resume, errors and orchestration forwarding; focused runtime and orchestration checks passed.
- The injected MCP command places global runtime arguments before `serve`. A real stdio test verifies handshake, scoped tools, read access and credential revocation.
- JSONL transport backpressure permits healthy bursts within a bounded deadline, and cancellation retains the original receive error. The shared transport and consumer regression run passed 173 tests.
- Codex accepts native MCP startup notices without mistaking `error: null` for a failure. ACP distinguishes legacy baseline stdio support from explicit modern capabilities. Pi preserves failed assistant results instead of completing them successfully.
- OpenCode generation detection follows the executable's reported version. Native message IDs match the upstream chronological `msg_` representation. Native echoed user parts, part IDs and reasoning metadata are tracked; valid empty deltas retain raw data without becoming invalid canonical content. The OpenCode suite passed 31 tests, including strict HTTP and native SSE regressions.
- Desktop widget regressions cover pending-dialog dismissal, close confirmation, draft preservation, IME composition, prompt history, keyboard routing, stopped/offline/archived empty states and narrow composer scrolling. The latest focused agent-chat group passed 71 tests. QA helpers passed 23 scenario tests, seven socket-probe tests and 32 macro fixtures.
- Test satellite transports return normal errors when their pools are closed during teardown. The orchestration group passed 43 tests with no detached closed-pool panics. Production shutdown behavior was not changed by that test repair.

Scoped formatting, whitespace and strict Rust Clippy checks passed for the repaired packages. The final app build passed on the Mac. The checks above overlap and should not be summed as one suite.

## Limits

Claude Code was not logged in on the Mac. Pi's existing OpenAI Codex refresh token was rejected with HTTP 401; the chat correctly recorded a failed turn. Cursor bridge, Muse and Antigravity executables were absent, and ACP Registry had no launch recipe. Their real inference remains unverified even though their transport/provider tests pass.

The mobile check used the production Dart client against the real local gateway, not a physical phone UI or WAN relay. New-worktree delegation, remote SSH chat execution and background-task shutdown races were not exercised live in this round. A possible late task wake during shutdown was identified by source review but not reproduced and is not claimed as repaired.

Cold startup briefly displayed runtime/quota errors before the fixture projects returned. Locked-machine captures returning `cgWindowNotFound` were treated as inconclusive. No database reset, account login, tool installation or system security changes were used to make a test pass.

## Reproduction

See [the QA helper readme](../tool/qa/readme.md) for bounded native scenarios and the Computer Use macro, and [the mobile gateway instructions](../mobile/tool/qa/readme.md) for pairing checks. Private native AX/JPEG captures and sanitized protocol reports remain under the Mac QA mirror's `.qa/` job directories. They are evidence artifacts, not shipped app resources.

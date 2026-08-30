# GPUI crash and state review

## Scope and result

Review date: 2026-08-29. Branch: `feat/rust-desktop-migration`, base `9b05e757`. GPUI 0.2.2, Zed revision `5218009a2d338898083b4789f5c5fd37ddc73b70`. Live validation is macOS debug only. Codex Chat, tray, Dock badges, and hide-on-close remain excluded.

The AI Assist opening crash is fixed in the working tree. Five additional findings remain open below. This is a crash/state-safety review, not a new certification of visual parity or all operating systems.

## Fixed: AI Assist fields missing at render time

`settings_panes/quotas_ai.rs` rendered five prompt operations, while `app_helpers.rs` initialized instruction textareas for only three. Rendering Reading Diffs called `expect("settings textarea should exist")`; Speech Messages had the same missing field. The old binary reproduced the panic at `2026-08-30T02:54:11.599Z`, matching the earlier user crash at `02:38:22.510Z`.

One catalog now defines the prompt operations used by input creation, select creation, select synchronization, rendering, and group navigation. Speech Messages is also searchable. Four regression tests cover field coverage, saved multiline/Unicode values, group order, and search routing.

## Open findings

### P1: Unicode terminal search generates invalid UTF-8 highlight ranges

Location: `experiments/alera-gpui/src/terminal.rs:598-613`, consumed by `app/terminal_surface.rs:464-473`.

Case-insensitive search computes byte offsets in `text.to_lowercase()` and applies them to the original text. Unicode lowercase can change byte length. Searching `i` in `İstanbul` yields `0..1`, which ends inside the original two-byte `İ`. The current GPUI `StyledText::with_highlights` asserts that both endpoints are character boundaries and panics in debug builds. Clamping to `text.len()` does not fix a non-boundary endpoint.

Evidence: a standalone probe includes the actual Alera terminal modules and links the currently built GPUI library. It produced `original UTF-8 boundary: false` and `actual GPUI highlight panicked: true`. No shell session or user file was changed by the probe. A release crash has not been reproduced.

Required fix: return ranges in the original string, using a case-fold mapping or a matcher that preserves source byte offsets. Test length-changing lowercase, combining marks, and wide characters.

### P1: Cached terminal search ranges survive changes to the underlying row

Location: `experiments/alera-gpui/src/app/terminal_surface.rs:443-465`; matches are regenerated only by opening search or changing its query at `507-565`.

Output, ANSI redraws, resize/reflow, and scrollback eviction can change the text behind an existing match without changing the query. Rendering reuses the old byte ranges and only clamps their length. For example, search `a`, then let a TUI replace that row with `é`: the cached range remains `0..1` and triggers the same GPUI assertion. This is independent of Unicode case folding and happens with a plain ASCII query.

Evidence: the actual terminal/GPUI probe found `a`, processed `\r\x1b[2Ké`, reused the stored match as the app does, and reported `stale search after terminal output panicked: true`. Rendering also maps search rows using the visible row index instead of `line.source_row`, so restored-prompt compaction can highlight a different row.

Required fix: version/invalidate search results when terminal content or grid layout changes, map display rows to source rows, and reject invalid endpoints before rendering. Avoid rescanning the entire scrollback for every streaming byte.

### P2: Terminal search highlights are appended after a complete ANSI style run list

Location: `experiments/alera-gpui/src/app/terminal_surface.rs:457-473`.

`visible_lines` already supplies ordered styles covering every byte of the row. Appending search ranges makes that list overlap and go backwards. GPUI consumes the list sequentially; it does not merge overlapping highlight ranges. The probe produced 60 bytes of text runs for an actual 30-byte row. Since the original runs already consume the whole line, search decoration is outside the shaped text and is not visible as intended.

Required fix: split/merge ANSI and search styles into one ordered, non-overlapping run list, preserving foreground, font, and background attributes. Test multiple hits in styled and unstyled lines.

### P2: Claude profile reordering does not validate its source index

Location: `experiments/alera-gpui/src/app/claude_profile_dialog.rs:119-125`.

The move handler validates only the target index, then calls `Vec::swap(index, target)`. A stale last-row callback can retain index 1 after settings refresh/removal leaves one row; moving up produces a valid target 0 but an invalid source 1. `quotas_ai.rs` captures these numeric indices in row callbacks, and asynchronous settings refresh can replace the profile list.

Evidence: reproducing the exact guard and swap with a one-element list, source 1 and offset -1 passes the guard and panics with `index out of bounds`. The UI race itself has not been forced live; this is a conditional state-safety finding, not a claim that every reorder crashes.

Required fix: resolve the profile by stable identity at event time and validate both positions before reordering. The same identity should protect edit/remove actions from acting on a different profile after reordering.

### P2: A late project-settings save can overwrite another project's unsaved draft

Location: `experiments/alera-gpui/src/app/project_config_settings.rs:394-399`.

The save completion does not retain/check the project or generation that initiated it. Switching projects remains enabled while saving (`project_config_settings_render.rs:192-195`). If the user saves A, switches to B, and edits B before A's response arrives, A's completion clears the current `seed_signature` and reloads B. `seed` then replaces B's prompt, copy rules, and setup commands with persisted values. The error path likewise attaches A's failure to whichever project is now selected.

Evidence: verified callback/control/data flow in source. The latency-dependent sequence has not been executed against user project settings, to avoid changing those settings during the review.

Required fix: scope save completion to the initiating project/generation and protect draft revisions while an async read/save is in flight. Add a delayed-response test switching A to B before the response.

## Coverage

The initial static scan covered 169 Rust source files outside test-named files and embedded test modules, plus the shared-core wiring and the pinned GPUI text renderer. It identified 67 explicit panic/unwrap/expect/unreachable candidates. These are candidate counts, not defect counts. Direct source inspection followed the relevant producers, guards, callbacks, and consumers.

| Surface | Checks | Outcome |
| --- | --- | --- |
| Application, Agents, Quotas, AI Assist, Editor, Terminal Settings | Input/select initialization, map lookups, async state, open each pane | AI Assist fixed; Claude index finding open; 26 other input keys have producers |
| Keyboard, Text Actions, Projects, Mobile Devices, Agent Profiles | Empty/loaded states, missing selections, per-row actions, delayed response guards | Project save race open; all panes opened without another panic |
| Sidebar/workspaces/agents | Recursive tree cycle guards, missing workspaces, empty groups, row indices, stored preferences | No additional confirmed panic in reviewed paths |
| Tabs/splits/editor/explorer | Removed-tab cleanup, optional tab guards, generation checks, empty groups, list indices | No additional confirmed panic in reviewed paths; full drag stress test not repeated |
| Terminal | Byte ranges, original vs folded text, changed rows, text styles, selection, resize | Three independent search findings above |
| Search/replace, quick open | Unicode slicing, empty result navigation, missing paths, replacement ranges | No additional confirmed panic in reviewed paths |
| Source Control, history, diffs, PR/CI | Empty histories, optional diff paths, dialog variants, comments, escaped SVG regexes | Guarded `expect`/`unreachable` cases verified; no additional confirmed panic |
| Runtime, Resources, Quotas, Usage | Optional snapshots, JSON normalization, zero/missing counters, disconnected state | No additional confirmed panic in reviewed paths |
| Orchestration, Agent Canvas, Mobile | Optional selection, generation/identity checks, late responses, empty data | No additional confirmed panic in reviewed paths |
| Startup, updates, diagnostics | Thread/window/font creation, logging, async shutdown | Thread creation still uses `expect` in several places; resource-exhaustion behavior remains untested |

## Verification and limitations

- `make gpui-debug` rebuilt, signed, and launched one GPUI instance. The existing installed runtime was not stopped.
- `cargo test --manifest-path experiments/alera-gpui/Cargo.toml --bin alera-gpui --locked`: 171 passed, 0 failed. The dependency `block 0.1.6` emitted an existing future-incompatibility warning.
- Computer Use opened AI Assist and Speech Messages, then all eleven Settings panes. Each exposed the selected pane and retained the Settings dialog without exiting.
- The Settings search accessibility tree filtered to AI Assist for `Speech Messages`. A subsequent dropdown click was rejected as offscreen. Later workbench clicks did not produce distinct panel contents, and screenshots lagged behind accessibility state; those attempts are not accepted as panel or dropdown validation. No additional live-panel coverage is claimed from them.
- Screenshots and accessibility snapshots: `/tmp/alera-parity/crash-review-2026-08-29/`.
- Standalone local reproducer: `/tmp/alera-gpui-crash-review-probe.rs`. It includes production terminal modules and uses the same compiled GPUI dependency. Its panics are caught inside the probe; they do not close the user's app.
- New findings are documented, not silently fixed as part of this review. Only the already requested AI Assist repair and its navigation/search consistency were changed.
- Windows/Linux, release-mode crash behavior, out-of-resources thread creation, and latency-dependent UI races were not live-validated. Passing unit tests and navigation smoke checks do not establish that every feature/state is safe.

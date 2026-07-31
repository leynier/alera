# Architecture

## Decision

The feasible architecture is an Alera-specific GPUI client, not a fork of the Zed application shell. GPUI supplies the retained-mode UI and GPU rendering model, `gpui-component` supplies reusable input, code editor and Markdown pieces, and Alera's existing Rust boundaries continue to own runtime, Git, process and workspace behavior.

## Runtime Boundary

`alera-runtime-protocol` owns the protocol version, shared capability names and binary frame codec. `alera-runtime-client` owns control-file discovery, authentication handshake, concurrent request correlation, newline compatibility, binary terminal frames, event delivery and reconnect-safe handles.

The existing CLI now re-exports these shared crates, so extraction does not create a second protocol implementation. The GPUI bridge runs a Tokio runtime on a named background thread, uses bounded command and event channels, supports per-request deadlines, and never blocks GPUI rendering.

The client reads the runtime control file only to connect. It never opens or writes `runtime.sqlite`. Flutter and GPUI can therefore attach simultaneously and receive the same runtime change events without divergent persistence.

## UI Boundary

`AleraApp` owns selection and presentation state. The shell is divided into the title bar, activity rail, project/workspace sidebar, tab bar, activity surface and status bar. Visual values come from the local dark theme module and use Inter plus JetBrains Mono.

Runtime catalog activities render live JSON cards and a per-activity allowlisted action console. Workspace activities use typed services and purpose-built controls. This split kept the POC broad without pretending that raw JSON controls are the final product UX.

## Terminal

The runtime host remains the PTY owner. The GPUI client sends `createOrAttach`, `write`, `resize`, `setOutputPaused` and `detach`; terminal bytes arrive through negotiated length-prefixed binary frames. The emulator keeps 10,000 scrollback lines, responds to PTY write events, supports bracketed paste, and maps keyboard input without a frame scheduler.

Incoming terminal output calls `cx.notify()` only when bytes arrive. Idle terminals have no animation loop. Streaming benchmarks deliberately batch four writes into one 33 ms update to compare against Flutter's current 29 flushes/s cadence.

The implemented renderer uses `alacritty_terminal` 0.26. Zed's terminal architecture was useful as evidence for separating PTY ownership, terminal state and rendering, but no Zed product crate or application shell was copied. Zed currently embeds its own Alacritty fork, while the POC uses the published crate directly.

## Workspace And Git

The workspace worker canonicalizes every requested path and rejects escape outside the selected root. It handles directory listing, bounded text reads, conflict-aware saves, search and replace, Mermaid rendering and image resolution off the UI thread.

Git uses the exact `alera_native::api::git` boundary. GitHub operations use the `gh` CLI through `alera_native::api::process::process_run`, preserving Alera's windowless and injectable process policy. Destructive discard and forge actions require a second explicit click.

## Dependency Choices

| Need | Selected | Reason |
| --- | --- | --- |
| Windowing and retained UI | `gpui` 0.2.2 | Native Rust rendering, Wayland/X11 features, no Flutter frame pipeline |
| Inputs, editor and Markdown | `gpui-component` 0.5.1 | Multiline input, code-editor mode, Tree-sitter highlighting and `TextView` |
| Terminal state | `alacritty_terminal` 0.26 | Pure Rust, direct cell access and shortest integration path |
| Alternative VT | `libghostty-vt` | Fastest bakeoff result and broader modern terminal behavior, but a changing C API |
| Mermaid | `gpui-component` Mermaid stack | In-process SVG output, no browser dependency |
| Images | GPUI `Image` | Native SVG and raster rendering |
| Git | Alera `alera_native` | Preserves libgit2, credentials and error semantics |
| GitHub | `gh` through Alera process API | Reuses authenticated CLI and avoids a second OAuth implementation |

Primary references used for the dependency assessment are [GPUI](https://www.gpui.rs/), [gpui-component 0.5.1](https://docs.rs/crate/gpui-component/0.5.1), [Zed](https://github.com/zed-industries/zed), [Ghostty](https://github.com/ghostty-org/ghostty) and [Ghostling](https://github.com/ghostty-org/ghostling).

## Migration Shape

A production migration should remain incremental. First ship the shared runtime crates and harden the GPUI terminal. Then replace one workspace surface at a time behind an experimental launcher. Flutter remains the release client until the feature matrix, accessibility, crash recovery, packaging and platform coverage reach release criteria.

# GPUI POC Implementation Plan

## Spec

The POC answers whether Alera Desktop can be rebuilt as a Linux-native GPUI client while preserving the existing Rust runtime host, persisted catalog and terminal sessions. It targets Wayland and X11, runs beside the Flutter client, and exercises the selected daily workflows with real data and mutations.

Success means that the GPUI client connects to the installed runtime host without reading `runtime.sqlite`, renders a recognizable Alera workbench, operates real terminal and workspace workflows, preserves explicit confirmation for destructive actions, and passes the agreed performance gate.

The audience is the Alera maintainers deciding whether to fund a staged migration. Browser, updater, PDF preview, emulator embedding, account/OAuth, SSH, LSP, macOS and Windows are non-goals for this POC.

## Design

The runtime wire protocol and client are shared Rust crates. Flutter and GPUI remain separate presentation clients, and the runtime host remains the single owner of sessions and catalog state.

The GPUI process owns a background Tokio bridge and forwards runtime events into GPUI entities. File, search, preview and forge work run outside the GPUI render path. Git operations reuse `alera_native` APIs and process execution reuses Alera's windowless process boundary.

The terminal renderer uses `alacritty_terminal` for the implemented POC because it offers a stable Rust API and the shortest integration path. A reproducible bakeoff retains `libghostty-vt` as the performance-leading candidate for a production terminal phase.

## Tasks

- Extract shared protocol constants, frame codec and reusable desktop runtime client.
- Build the isolated GPUI shell and connect it to real projects, workspaces, tabs and layouts.
- Implement a runtime-backed terminal with binary output, input, resize, paste, scrollback and reconnect behavior.
- Implement Explorer, workspace search and replace, editor save safety, Markdown, Mermaid and image previews.
- Implement Git operations, GitHub pull request and CI operations, and AI Text generation.
- Expose live agent, quota, resource, orchestration, settings, device and diagnostic state with scoped mutation consoles.
- Validate Wayland, X11, runtime coexistence, VT correctness and the agreed performance gate.
- Record supported, partial and excluded behavior without treating a POC surface as production parity.

## Tests

- Unit-test protocol framing, handshake order variants, terminal encoding, path safety, remote parsing and mutation allowlists.
- Run a live runtime smoke suite against the installed host.
- Compile the GPUI client for both Wayland and X11 feature sets.
- Run the exact 2.56 MB VT bakeoff and terminal restore benchmark in release mode.
- Compare GPUI streaming CPU, idle frames and input encoding with the existing Flutter benchmarks on the same Linux machine.
- Launch Flutter and GPUI concurrently against the same runtime host and verify that stopping GPUI does not stop Flutter or the host.

## Assumptions

- The installed Alera runtime host matches protocol version 4 and advertises additive capabilities for the selected features.
- Linux has a working graphical Wayland or X11 session and the runtime `libxkbcommon-x11.so.0`; `build.rs` supplies the missing development linker alias when required.
- GitHub operations may rely on the already installed `gh` CLI through Alera's process boundary.
- Licensing is intentionally deferred for this POC. A production decision must perform a fresh dependency and copied-code audit.

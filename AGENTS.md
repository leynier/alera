# AGENTS

## Scope

This file applies to the entire repository. Nested `AGENTS.md` files may add rules for a subdirectory; when they do, follow both the root file and the nested file.

This document defines contributor and agent governance only. It does not change runtime APIs, schemas, or protocol types.

## Core Operating Principles

- Prefer clear, traceable work over implicit progress. Keep the user informed about what is being done, what remains, and any relevant blockers.
- Use these instructions by default. If a specific task requires a different approach, explain the reason clearly before deviating.
- Keep plans and outputs portable across agent runtimes unless the user asks for behavior tied to a specific tool.
- Avoid unnecessary complexity. Choose the simplest approach that satisfies the user's stated goal and preserves correctness.

## Task Tracking

- Agents MUST use the available task-tracking tool whenever the work has multiple steps, meaningful uncertainty, or a non-trivial implementation path.
- Track tasks as pending, in progress, and completed so the current state of the work stays explicit.
- Update the task list as work progresses, not only at the end.
- Keep task entries concrete and outcome-oriented. Each task should describe a verifiable unit of work.
- When new work is discovered, add it to the tracker instead of relying on memory.
- When a task becomes irrelevant, mark or explain it rather than silently dropping it.
- Before finishing, reconcile the tracker with the actual work completed and call out anything intentionally left undone.

## Code Generation Workflow

- Riverpod providers MUST use code generation (`riverpod_generator`) rather than hand-written provider declarations.
- This repository does NOT use a `build_runner` watcher. Agents MUST NOT run `build_runner watch` or keep any background code-generation process alive.
- When a planned batch of edits touches Riverpod, Drift, or `dart_mappable` generated surfaces, agents MUST finish the planned edits first and then regenerate code once for the whole batch with `flutter pub run build_runner build -d`. Do not regenerate after every individual edit.
- The one-shot generation MUST run before `dart format`, `flutter analyze`, and tests, so formatting, static analysis, and test runs always see the final generated code.
- Agents MUST verify the regenerated files are included alongside the source changes that produced them.

## Native Rust Layer

- Alera runs a Rust layer under Flutter through `flutter_rust_bridge` v2. `rust/` is a Cargo workspace whose root package is the FRB git library `alera_native` (`cdylib`/`staticlib`) and whose member `alera-cli` is the terminal-host sidecar binary (see *Process And Terminal Safety*). The Flutter build plugin is at `rust_builder/`, and the generated Dart bindings at `lib/src/rust/` (committed, not regenerated in CI). `RustLib.init()` runs in `lib/main.dart` before `runApp`. The FRB native build (`cargo build --manifest-path rust/Cargo.toml`, no `-p`) compiles only the root `alera_native` package, so it never drags in the sidecar's dependencies.
- Git operations MUST go through the `GitBackend` boundary (`lib/src/shared/infra/git/`), not by spawning the `git` binary via `ProcessRunner`. The production implementation `RustGitBackend` calls the Rust API; local operations use `git2` (libgit2) and only `clone` is delegated to the `git` CLI (via the `git_cmd` crate) so the system credential helper keeps working.
- Keep the `GitBackend` interface free of generated bridge types: `RustGitBackend` is the only place that imports `lib/src/rust/api/git.dart`, and it translates the native `GitError` into the domain `GitException` hierarchy. Services depend on `GitBackend`; unit tests use the shared `FakeGitBackend` (`test/unit/fake_git_backend.dart`).
- After changing the Rust API surface (`rust/src/api`), regenerate bindings with `make frb-generate` (`flutter_rust_bridge_codegen generate`) and commit the result. Building the desktop app requires a Rust toolchain (`rustup`), pinned by `rust/rust-toolchain.toml`; CI installs it via `dtolnay/rust-toolchain`. The shared `rust/Cargo.lock` is committed and the native hooks build with `--locked`, so a regenerated lock must stay complete for both crates.

## Spec-Driven Planning

When planning is needed, use a spec-driven development flow. Do not jump straight from a vague request to implementation if important product or technical decisions are still undefined.

### Spec Discovery

- First clarify the desired behavior, success criteria, audience, inputs, outputs, constraints, and non-goals.
- Prefer discovering facts from the repository, environment, or existing documentation before asking the user.
- Ask targeted questions only for decisions that cannot be safely inferred.
- Convert ambiguous requests into explicit requirements before designing a solution.

### Design

- Define the implementation approach after the spec is stable.
- Identify affected interfaces, data flow, dependencies, storage, permissions, error handling, and compatibility constraints when relevant.
- Surface meaningful tradeoffs and choose a default when one option is clearly safer or simpler.
- Keep the design aligned with existing project conventions.

### Tasking

- Break the design into ordered, concrete tasks that can be implemented and verified.
- Include validation steps as first-class tasks, not as an afterthought.
- Present plans using the structure: spec, design, tasks, tests, and assumptions.
- Make the plan decision complete: another engineer or agent should be able to execute it without inventing missing requirements.

## Clipboard Usage

- Use the clipboard when it helps transfer commands, snippets, paths, reports, or other information to the user efficiently.
- Prefer native clipboard commands for the user's operating system:
  - macOS: `pbcopy` and `pbpaste`.
  - Windows PowerShell: `Set-Clipboard` and `Get-Clipboard`.
  - Linux Wayland: `wl-copy` and `wl-paste`.
  - Linux X11: `xclip` or `xsel`.
  - WSL: `clip.exe` when copying content into the Windows clipboard is appropriate.
- Tell the user what was copied, especially when the clipboard content is long or operationally important.
- Avoid placing secrets, tokens, credentials, personal data, or destructive commands on the clipboard unless the user explicitly asks for it or the task clearly requires it.
- If clipboard tooling is unavailable or unsafe in the current environment, provide the exact command or content for the user to copy manually.

## Git And Pull Requests

- Use Conventional Commit style for commit messages.
- Write commit messages and pull request titles in English unless the user explicitly requests another language.
- Commit messages and pull request titles MUST be lowercase.
- Prefer concise commit subjects that clearly describe the change, such as `fix: handle empty clipboard input`, `docs: update agent workflow rules`, or `chore: add repository instructions`.
- Keep pull request descriptions short and useful. Include a brief summary, validation performed, and any important risks or notes when relevant.
- Never add the agent as a coauthor, assisted-by, generated-by, or equivalent attribution in commits, pull requests, pull request descriptions, or related metadata unless the user explicitly asks for it.
- Keep changes scoped to the user request. Do not fold unrelated refactors into implementation work.
- This document SHALL remain organized with non-numbered section headers.

## Communication Expectations

- Be direct and specific. Explain decisions, blockers, and verification results in practical terms.
- Do not hide uncertainty. If something is assumed, say so.
- Keep progress updates short but useful during longer work.
- When implementation is complete, summarize what changed, how it was verified, and any remaining risk or follow-up.

## Worktree Safety

- Always read and edit files from the active working directory.
- Never follow absolute paths copied from another agent or another worktree unless they are revalidated in the current checkout.
- Before mutating git state, check for existing local changes and preserve user work.
- If `.git/index.lock` exists, confirm no git process is active before removing it.

## Code Comments

- Add comments only when they explain a non-obvious reason: safety, platform behavior, compatibility, release constraints, or a design-system rule.
- Keep comments brief. Do not narrate what the code already says.

## Markdown Style

- Do not hard-wrap Markdown prose. Keep each paragraph or list item on one line unless the line break is semantically meaningful.
- Preserve explicit line breaks in tables, code fences, lists, and generated templates where Markdown syntax requires them.
- Never use em-dashes (`—`) anywhere in the repository: not in Markdown, code comments, UI copy, CLI output, or tests. Use a plain hyphen (`-`) instead.

## Naming

- Do not create vague modules named `helpers`, `utils`, `common`, `misc`, or similar dumping grounds.
- Name files and types after the domain concept they model, such as `workspace_folder_opener.dart` or `update_archive.dart`.
- If a file name starts feeling generic, split responsibilities before adding more code.
- Avoid files longer than 500 lines. When a file approaches that size, split it by concrete domain responsibility instead of adding more unrelated code.

## Flutter UI Rules

- Flutter UI values MUST come from `AleraTokens` and `ThemeData`.
- New UI code MUST NOT introduce ad-hoc visual literals for color, spacing, radius, duration, or typography when an existing token/theme value covers the role.
- `Colors.transparent` MAY be used only for explicit transparent states.
- Visible UI copy MUST use title case (e.g., "New Workspace", "AI Text").
- The active app theme strategy SHALL remain dark-mode-only in this version.
- Typography MUST remain fixed to Inter for general text and JetBrains Mono for monospaced text.
- The canonical design-system reference is `docs/ui-styleguide.md`.
- Shared, reusable UI components live in `lib/src/design_system/`, grouped by role and prefixed `Alera`. New screens MUST reuse these before introducing ad-hoc widgets; a genuinely new shared component belongs here, with a co-located `*.preview.dart`.
- Design-system components MUST be presentational: data and callbacks in via parameters, no Riverpod reads and no native (`dart:io`/`dart:ffi`) code, so they stay previewable. Wire providers in a thin feature-level wrapper instead.
- Preview functions MUST use the `@AleraPreview` annotation (not the bare `@Preview`). Launch with `flutter widget-preview start`.

## Keyboard Shortcuts

- Shortcut-able actions live in `lib/src/features/keyboard/domain/keyboard_action.dart` as the single source of truth (id, label, group, per-platform defaults, allow-in-terminal flag). New shortcut-able actions MUST be added to that registry rather than wired through ad-hoc `Shortcuts`/`CallbackShortcuts` widgets.
- Behavior is dispatched from one place: `KeyboardCommandDispatcher`. Reuse existing controller methods and the shared dialog launchers in `workbench_dialog_launchers.dart`; do not duplicate dialog flows.
- Matching is centralized in `KeybindingResolver` and consumed by exactly two call sites: the global `KeyboardShortcutsScope` (shell-mounted) and the `TerminalSurface` `onKeyEvent` hook (terminal-focused interception). Do not add a third matcher or a global `HardwareKeyboard` handler.
- The `Mod` modifier is platform-neutral (⌘ on macOS, Ctrl elsewhere). Use the canonical token form (`Mod+Shift+BracketRight`) in defaults; symbol aliases (`,`, `[`) are accepted at parse time.
- Respect the `TerminalShortcutPolicy` setting: under `terminalFirst`, only bindings with `allowInTerminal: true` may intercept while a terminal is focused.

## Cross-Platform Desktop Rules

- Alera targets macOS, Windows, and Linux.
- Use `Platform` checks or framework abstractions for platform-specific behavior; do not assume POSIX paths or commands.
- Use `path` package utilities for filesystem paths.
- Keep terminal, process, workspace, updater, and release code explicit about platform support.
- UI shortcut labels must match the actual shortcut behavior for the current platform.
- The application menu uses the global `PlatformMenuBar` on macOS and a compact Flutter menu beside the app name on Windows/Linux, so those platforms do not lose client-area height to a native `GtkMenuBar` or `HMENU`. Menu actions share `lib/src/features/app_menu/presentation/app_menu_actions.dart`; keep their labels and behavior in sync across the platform presentations. Menu controls MUST NOT register keyboard accelerators, so keys like Ctrl+C keep flowing to text fields and the terminal-first shortcut policy. Because Alera is dark-only, Windows enables process-wide dark mode through `windows/runner/win32_dark_mode.cpp`.

## Flutter Performance

- Performance is a product requirement. UI changes must keep the Flutter frame pipeline responsive and avoid unnecessary rebuilds, layout churn, blocking I/O, and heavy synchronous work.
- Do not run expensive parsing, filesystem traversal, process output processing, hashing, serialization, or other CPU-heavy work on the main isolate when it can reasonably run in another isolate.
- Prefer isolate-backed workers, `compute`, streamed processing, or incremental batching for work that can grow with repository size, terminal output size, release artifact size, or user data size.
- Keep main-isolate work limited to UI state coordination and small transformations needed for rendering.
- When a main-isolate implementation is intentionally kept, document the reason in code or PR notes if the workload could plausibly become large.

## Process And Terminal Safety

- Treat shell and terminal behavior as user-visible product behavior.
- Do not assume a local shell exists when the code path could later support remote or constrained environments.
- Keep command execution behind `ProcessRunner` or a similarly injectable boundary.
- Tests for command construction should verify Windows, Linux, and macOS variants when behavior differs.
- Cases in `orchestration_review_regressions::deferred_delivery_cases` fail intermittently under the parallelism of a full `make rust-test` and pass in isolation; they drive real PTYs, and which case flakes varies between runs (`coordinator_promotion_waits_for_deferred_delivery`, `cancelling_active_worker_interrupts_before_idle_banner_delivery`, and `push_on_idle_does_not_duplicate_in_flight_batches` have all been observed). Re-run the named case on its own before treating a red `rust-test` as a real regression, and do not chase it as fallout from an unrelated change.
- Use the lowercase repository `makefile` for app/CLI debug workflows instead of keeping one-off commands in chat or local notes. Its debug targets must remain shell-neutral and route platform-specific behavior through Dart scripts under `tool/debug/` so they work from PowerShell 7 on Windows as well as Linux and macOS shells. `make help` lists available rules. `make app-debug` runs the Flutter app with the development CLI fallback (a `cargo run` of the Rust sidecar), `make cli-build` compiles the Rust `alera` CLI sidecar (the `rust/alera-cli` crate) with cargo, `make app-debug-bundled-cli` runs the app against the compiled sidecar, `make host-debug` runs the Rust `alera terminal-host` in the foreground, and `make rust-test` runs fmt/clippy/test for the crate.
- When debugging persistent terminal behavior, inspect process separation with `make debug-processes`; the UI process should be the Flutter app and the host process should be `alera terminal-host`. Use `ALERA_HOST_EMPTY_SHUTDOWN_SECONDS`, `ALERA_HOST_DETACHED_SHUTDOWN_SECONDS`, and `ALERA_HOST_SCROLLBACK_BYTES` when foreground host debugging needs non-default lifecycle or scrollback values. Use `make host-stop` only when intentionally ending the current debug host for this app id.
- The shipped `alera` CLI / terminal-host sidecar is the Rust crate under `rust/` (`rust/alera-cli`, binary `alera`). The native build hooks - `linux/CMakeLists.txt`, `windows/CMakeLists.txt`, and the macOS "Build Alera CLI Sidecar" Xcode phase - build it with `cargo build --locked` (Release app → `--release`, otherwise debug) and install the single binary into `resources/alera/alera[.exe]`. The toolchain is pinned by `rust/rust-toolchain.toml` and `rust/Cargo.lock` is committed; CI and the hooks build reproducibly with `--locked`. The Dart client-side and shared protocol files under `lib/src/features/workbench/infra/terminal_host/` stay active because they connect the app to the sidecar over the socket.
- PTY output framing is negotiated per client, never per host. A client asks for length-prefixed binary frames in its `hello` (`binaryFrames: true`) only when the control file advertises `RUNTIME_HOST_BINARY_FRAMES_CAPABILITY`; the host answers with what it granted and every later byte on that connection is framed. This MUST NOT bump `aleraTerminalHostProtocolVersion`, because a version mismatch makes the app treat a live host as unusable, and because the `alera` CLI (`runtime_host_client.rs`) and older apps must keep getting newline-delimited JSON from the same host. The switch travels **in band**, as a `ClientFrame::UpgradeToBinary` queued behind the hello response on the same lane: a shared flag could flip before the response was written and frame a response the client is still reading as a line. Frame layout lives in `rust/alera-cli/src/terminal_host/frame_codec.rs` and its Dart mirror `terminal_host_frame_codec.dart`, which has a fixed-bytes test so the two cannot drift.
- Per-session CPU and memory sampling lives in the sidecar, never in the app: the host already owns the PTYs and the `sessionId -> workspaceId -> tabId` relation, and a process-table sweep must stay off the Flutter main isolate. `Session.shell` MUST be cleared on exit and terminate, because the OS recycles pids and a stale value silently attributes a stranger's process to a dead session. Clearing alone is not enough: the OS reaps the shell before the reader thread reports the exit, so the field also carries the start time observed at spawn (`seal_shell_process`), and a sweep attributes a subtree only while the pid still holds that start time (`ProcessIndex::holds`). A root that fails the check reports `measured: false` instead of billing a stranger's memory to a terminal. The comparison has second resolution, so it bounds that window rather than closing it. When summing subtrees, claim the session roots before the host root and share one `claimed` set: every PTY shell is a child of the runtime host, so the opposite order swallows all of them into one unattributed row. `resources.snapshot` and `resourceMonitorV1` are additive and MUST NOT bump `aleraTerminalHostProtocolVersion`. How many sweeps `sysinfo` needs before process CPU is meaningful differs per platform (3 on Windows, 2 on Linux and macOS), and CI runs `cargo test --workspace` on Linux only, so changes to the sampler MUST be re-verified on a real Windows and macOS machine.
- `Session::terminate` kills the shell's whole process tree, not just the shell. `portable-pty`'s killer reaches the direct child only (`SIGHUP` on unix, `TerminateProcess` on Windows), and the kernel hangup that would sweep up the rest reaches only the controlling terminal's foreground group, so an agent CLI that daemonizes or an MCP server outlives the tab and keeps holding the worktree's working directory. The ordering in `shell_tree_termination.rs` is load-bearing and MUST NOT be rearranged: capture the subtree BEFORE the root is signalled, because a dead root's children reparent away and stop being reachable through it, and any row still naming the vacated pid is a pid-recycle coincidence. For the same reason a session whose shell already exited (`shell` cleared) MUST NOT be swept. Nothing is signalled without positive identity proof from the sealed start time: a failed or overrunning sweep leaks a tree, which is the correct way to fail, because guessing wrong signals a stranger's tree instead.
- Runtime change events carry an optional scope id (`workspaceId`, `projectId`) and an absent or empty scope means wildcard: every watcher refreshes. The app can attach to an already-running sidecar, so an older host broadcasting an empty payload MUST keep working. Emit these events through the helpers in `rust/alera-cli/src/terminal_host/server/runtime_change_broadcasts.rs` and pass `None` whenever the mutation really is broader than one workspace or project. Never guess a scope: the wildcard is the safe value, a wrong id silently stops watchers from updating. Adding a scope field is additive and MUST NOT bump `aleraTerminalHostProtocolVersion`, because a version mismatch makes the app treat a live host as unusable.

## Build Flavors

- Alera builds in two flavors selected by the `ALERA_FLAVOR` environment variable: `dev` (default) and `release`.
- The `dev` flavor uses `dev.leynier.alera.dev` as bundle identifier / GTK `APPLICATION_ID`, `alera-dev` as Windows/Linux binary name, and `Alera Dev` as the display name in the Dock, taskbar, and window title. This lets a locally running dev build coexist with an installed release build without sharing user-data directories (which are keyed by bundle id / application id).
- The `release` flavor keeps bundle identifier `dev.leynier.alera` and display name `Alera`. Its on-disk executable is `Alera` on Windows (`Alera.exe`) and macOS (`Alera.app`, via `ALERA_PRODUCT_NAME`), while the Linux binary stays lowercase `alera` by POSIX convention. `desktop_updater` copies the macOS bundle to `dist/` under the lowercase pubspec package name (`alera.app`), so `release-cut.yml` renames it to `Alera.app` before packaging the release tarball. The release flavor MUST be selected by CI for any artifact intended to be installed by an end user. `.github/workflows/desktop-build.yml` and `.github/workflows/release-cut.yml` set `ALERA_FLAVOR: release` at the job env level.
- The makefile defaults `ALERA_FLAVOR` to `dev` and forwards `--alera-flavor` to `tool/debug/alera_debug.dart`. The debug tool regenerates `macos/Runner/Configs/Flavor.xcconfig` (git-ignored) before each `flutter run` and exports `ALERA_FLAVOR` so the Windows/Linux CMake branches and the Dart-side `kAleraFlavor` constant agree. `Flavor.example.xcconfig` documents the dev-flavor values for reference.
- Auto-update MUST remain disabled on dev builds regardless of any other flag. The guard lives in `effectiveAutoInstallEnabled` (see `lib/src/core/build_flavor.dart`) and is applied by `AleraUpdateConfig.fromEnvironment()`.
- The canonical flavor identity strings (`Alera`, `Alera Dev`, `dev.leynier.alera`, `dev.leynier.alera.dev`, and the `release` / `dev` selectors) live in `lib/src/core/build_flavor.dart`. The macOS xcconfig generator in `tool/debug/alera_debug.dart` imports them so the regenerated `Flavor.xcconfig` cannot drift from the runtime Dart constants.
- The generated `macos/Runner/Configs/Flavor.xcconfig` reflects whatever flavor was most recently prepared by `tool/debug/alera_debug.dart`. If a contributor wants to rehearse a release build locally after running a dev `make` target, they MUST re-prepare the release flavor first (e.g. `ALERA_FLAVOR=release make app-debug`) or delete `Flavor.xcconfig` - otherwise `flutter build macos --release` will inherit the stale dev override.

## Release And Update Rules

- GitHub Actions work must follow `.github/AGENTS.md`.
- Release script work must follow `tool/release/AGENTS.md`.
- Stable auto-update MUST remain disabled until release builds are signed and notarized/trusted for the relevant platform.
- Release automation must publish drafts first, verify all required assets and update manifests, and only then publish public releases.

## Reference Projects

- `reference_projects/` contains non-runtime references for agentic development and orchestration patterns.
- `reference_projects/orca` is the primary reference for ADE-style collaboration, contribution workflow, release gates, and agent-facing project guidance.
- Reference projects MUST NOT become runtime dependencies of Alera.

## Documentation Maintenance

- After every feature, refactor, fix, or infrastructure change, explicitly consider whether `AGENTS.md`, nested `AGENTS.md` files, `readme.md`, `docs/`, `.github/CONTRIBUTING.md`, `SECURITY.md`, or release documentation need updates.
- If documentation does not need updates, mention that decision in the final summary or PR notes when the change is user-visible, architectural, process-related, release-related, or contributor-facing.
- Keep documentation aligned with implemented behavior. Do not document planned behavior as active behavior.

## Nested Instructions

- `landing/AGENTS.md` applies under `landing/`.
- `mobile/AGENTS.md` applies under `mobile/`.
- `test/AGENTS.md` applies under `test/`.
- `.github/AGENTS.md` applies under `.github/`.
- `tool/release/AGENTS.md` applies under `tool/release/`.

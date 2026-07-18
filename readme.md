<h1 align="center">
  <a href="https://alera.build"><img src="assets/logo/alera-logo.png" alt="Alera" width="64" valign="middle" /></a> Alera
</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-blue?style=for-the-badge" alt="Supported platforms" />
  <img src="https://img.shields.io/badge/Built%20with-Flutter%20%2B%20Rust-3DDC84?style=for-the-badge&logo=flutter&logoColor=white" alt="Built with Flutter and Rust" />
  <img src="https://img.shields.io/badge/Engine-Ghostty%20VTE-111111?style=for-the-badge" alt="Ghostty VTE engine" />
  <a href="https://github.com/leynier/alera/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="License" /></a>
</p>

<p align="center">
  <strong>The native, performance-first agentic development environment.</strong><br/>
  Run Claude Code, Codex, Grok Build, Amp, Antigravity, OpenCode, Copilot, Cursor or any other CLI agent side-by-side, each in its own Git worktree, all tracked in one place.<br/>
  Built with <strong>Flutter + Rust + Ghostty</strong>. No Electron. No bundled Chromium. Available for <strong>macOS, Windows, and Linux</strong>.
</p>

<p align="center">
  <a href="#install"><strong>Get Alera →</strong></a> &nbsp;·&nbsp;
  <a href="https://alera.build"><strong>alera.build</strong></a> &nbsp;·&nbsp;
  <a href="roadmap.md"><strong>Roadmap</strong></a>
</p>

---

## Why Alera

Agentic coding is the new bottleneck of developer tooling. Most "AI IDEs" today wrap a single chat backend inside an Electron shell: slow to start, heavy on RAM, locked to one provider, and limited to one task at a time.

Alera takes the opposite bet:

- **Bring your own agent.** Alera is terminal-first. Every CLI coding agent runs in its own real PTY, the way it was meant to. No proprietary chat layer, no vendor lock-in
- **Run many agents at once.** Each task gets its own Git worktree, its own tabs, and its own terminals, so Claude, Codex, Amp, and friends can work in parallel without stepping on each other
- **Native performance.** Flutter for a fast, consistent desktop UI. Rust for the PTY and process layer (`portable_pty`). Ghostty's VTE engine for terminal parsing. No Electron, no embedded browser, no JS event loop in the hot path
- **See what your agents are doing.** Lifecycle hooks for the most popular CLI agents stream their activity into Alera so you can tell, at a glance, which terminals are idle, working, or waiting on you
- **Track agent quotas.** A bottom status bar shows local or remote quota usage for Claude Code and CCS profiles, Codex, Kimi, Grok Build, Antigravity, MiniMax, and Z.ai
- **Never lose a terminal again.** Terminal sessions persist across restarts. Close the app, reboot the machine, come back, and your scrollback, processes, and layout are still there

---

## Supported CLI agents

Alera works with **any CLI agent**. The agents below ship with first-class integration today (icons, managed lifecycle hooks, and live activity tracking):

<p>
  <a href="https://docs.anthropic.com/claude/docs/claude-code"><kbd><img src="assets/agents/claude.svg" width="16" valign="middle" /> Claude Code</kbd></a> &nbsp;
  <a href="https://github.com/openai/codex"><kbd><img src="assets/agents/codex.svg" width="16" valign="middle" /> Codex</kbd></a> &nbsp;
  <a href="https://ampcode.com/manual#install"><kbd><img src="assets/agents/amp.png" width="16" valign="middle" /> Amp</kbd></a> &nbsp;
  <a href="https://antigravity.google/docs/cli-overview"><kbd><img src="assets/agents/agy.png" width="16" valign="middle" /> Antigravity (Agy)</kbd></a> &nbsp;
  <a href="https://opencode.ai/docs/cli/"><kbd><img src="assets/agents/opencode.png" width="16" valign="middle" /> OpenCode</kbd></a> &nbsp;
  <a href="https://cursor.com/cli"><kbd><img src="assets/agents/cursor.png" width="16" valign="middle" /> Cursor</kbd></a> &nbsp;
  <a href="https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli"><kbd><img src="assets/agents/copilot.svg" width="16" valign="middle" /> GitHub Copilot</kbd></a> &nbsp;
  <a href="https://pi.dev"><kbd><img src="assets/agents/pi.svg" width="16" valign="middle" /> Pi</kbd></a>
  <a href="https://x.ai/cli"><kbd><img src="assets/agents/grok.png" width="16" valign="middle" /> Grok Build</kbd></a>
</p>

Anything else that runs in a terminal (Gemini CLI, Goose, Kimi, Crush, Continue, Aider, your own scripts) works out of the box. Activity tracking is incrementally rolling out per agent.

---

## What you get today

Alera is in active development. These are the features shipping **right now**:

### 🗂️ Project & workspace registry

Register existing local folders or clone Git repositories from one place. Git-backed projects can spin up multiple **workspaces** backed by real Git worktrees: create a branch from a source branch or reuse an existing local branch, one task or experiment per workspace, fully isolated.

### 🌳 Worktree-native workflow

Every workspace is a worktree. Less branch juggling, fewer "wait, what was I working on?" moments. Switching contexts is instant, and your agents never collide on the same files.

### 🤖 Multi-agent terminals

Open multiple terminals per workspace, organised in tabs. Run Claude Code in one, Codex in another, Amp in a third, all in parallel and all visible at the same time. Each terminal is a full PTY backed by Rust (`portable_pty`) and parsed by Ghostty's VTE.

### 📡 Live agent activity tracking

Managed lifecycle hooks for Claude, Codex, Grok Build, Amp, OpenCode, Antigravity, Cursor, Copilot and Pi stream agent events into Alera. You can see which agents are **idle, working, or waiting on input** without staring at every terminal.

### 📊 Agent quota tracking

A bottom status bar keeps provider quota usage in sight while agents run: Claude Code and CCS profiles, Codex, Kimi, Grok Build, Antigravity, MiniMax, and Z.ai, resolved locally or remotely. Hover for the detailed breakdown, and know before an agent stalls that you're about to hit a limit.

### 🕸️ Inter-agent orchestration

Agents coordinate through orchestration protocol v2: workspace-scoped coordinator runs, atomic spawn/readiness/acceptance, durable task ownership, context-aware completion and cancellation, runtime liveness leases, structured results, decision gates, and persistent messaging. A workspace has at most one active coordinator while unrelated workspaces can run concurrently.

### 💾 Persistent terminal sessions

Close Alera. Reboot. Reopen. Your terminals, their scrollback, their layouts, and the processes you launched are still there. Long-running agent runs survive restarts instead of vanishing with the window.

### 🎨 Terminal customization

Per-terminal configuration: font, size, theme, behaviour. Built on top of the same engine that powers Ghostty for predictable, high-fidelity rendering.

### 🗃️ File explorer, search & previews

Browse workspace folders in a tree-based explorer with a git-ignored toggle and inline rename. Search and replace across the workspace with regex and include/exclude patterns. Preview Markdown, PDFs, Mermaid diagrams, and images in dedicated tabs, right next to your terminals.

### 🔀 Visual source control

Review structured diffs side-by-side or unified, with per-file and aggregated views. Stage, commit, amend, stash, and discard visually, with AI-powered commit message suggestions. A collapsible commit history graph (with a draggable divider) shows HEAD and upstream at a glance, and submodules get lazy read-only status and diff inspection.

### ✅ Pull requests & checks

Work with pull requests per worktree on GitHub and Azure DevOps without leaving Alera: create, edit, comment (with Markdown), toggle draft status, and merge. CI checks are grouped by status with drill-down into check details. PR titles and descriptions can be AI-generated from the branch changes, and the workspace menu opens the repository in your browser in one click.

### 🖥️ Truly native, truly cross-platform

One codebase, three real desktops. Native window chrome, native keyboard shortcuts (⌘ on macOS, Ctrl elsewhere), dark-mode-first UI built on the Alera design system. No Electron, no embedded browser, no 400 MB install.

### 🔄 Built-in update channel

Stable and release-candidate update channels with a manual download flow today, signed automatic installs as platform trust requirements land.

### 📱 Mobile companion foundation

A separate Flutter app lives under `mobile/` for Android and iOS. Pairing starts from **Settings → Mobile Devices** in the desktop app, which shows a scannable QR pairing offer (with a copy-JSON fallback) and manages the gateway, active offers, and paired devices. The mobile app stores device tokens in platform secure storage, connects to the runtime-host mobile WebSocket gateway, lists projects/workspaces/branches, and can start or attach to a hosted terminal session. The same lifecycle (settings, pairing offers, device rename/revocation, gateway) is also scriptable through `alera mobile ...`.

---

## What's next

Alera is shipping fast. A non-exhaustive list of what's on the roadmap:

- **SSH worktrees**: run agents on remote machines as if they were local
- **Mobile live transport expansion**: add agent status, file review, and richer workspace controls to the mobile app
- **Code editing with LSP support**: full editing with language-server autocomplete and diagnostics
- **Git conflict resolution**: resolve merge conflicts visually with AI-assisted three-way merge
- **Embedded browser & browser use**: give agents a real browser to drive
- **More forge & tracker integrations**: GitLab pull requests and checks, Linear and issue-tracker linking per worktree
- **Voice, automations, MCP management, skills, and more**

See the full [roadmap](roadmap.md) for the complete picture, including difficulty/utility scoring per feature.

---

## Install

> Public release artifacts and download links are being finalized. Track [releases on GitHub](https://github.com/leynier/alera/releases) or visit **[alera.build](https://alera.build)** for the latest.

### Run from source

Alera is a Flutter desktop app. You'll need a recent [Flutter SDK](https://docs.flutter.dev/get-started/install) and a working Rust toolchain (`rustup`). The Rust workspace under `rust/` provides both the native terminal-host sidecar (`alera-cli`) and the git layer (`alera_native`, compiled into the app through `flutter_rust_bridge`).

```bash
git clone https://github.com/leynier/alera.git
cd alera
make init-submodules
flutter pub get

# Pick your platform:
flutter run -d macos
flutter run -d windows
flutter run -d linux
```

By default a local build runs as **Alera Dev** (`dev.leynier.alera.dev`) so it can coexist with an installed release without sharing user data. Set `ALERA_FLAVOR=release` to opt back into the release identifier.

Regenerate the `flutter_rust_bridge` bindings after changing the Rust API (`rust/src/api`) with `make frb-generate`.

---

## Performance & architecture

Alera is built around three deliberate engineering choices:

```diagram
╭──────────────────────────╮     ╭──────────────────────────╮     ╭──────────────────────────╮
│         Flutter          │     │           Rust           │     │      Ghostty VTE         │
│    Native desktop UI,    │ ──> │   PTY + process layer    │ ──> │    Terminal parser &     │
│   shell, design system   │     │    via portable_pty      │     │  renderer (no Electron)  │
╰──────────────────────────╯     ╰──────────────────────────╯     ╰──────────────────────────╯
```

- **Flutter** for the desktop shell, design system, and UI: fast startup, consistent look across macOS / Windows / Linux, fully native rendering
- **Rust** for the PTY and process boundary through [`portable_pty`](https://crates.io/crates/portable-pty), so spawning, signalling, and resizing real terminals stays predictable on every OS
- **Ghostty's VTE** through `ghostty_vte_flutter` for terminal parsing: the same engine that powers the Ghostty terminal emulator
- **Drift / SQLite** for local persistence of projects, workspaces, tabs, layouts, settings, and terminal state
- **No Electron, no Chromium, no Node runtime** in the app, and no plan to add them

For more, see [`docs/architecture.md`](docs/architecture.md).

---

## Inspired by great open source projects

Alera stands on the shoulders of brilliant work in the agentic dev and terminal space. Special thanks to:

- **[Orca](https://github.com/stablyai/orca)**: the primary inspiration for worktree-oriented, multi-agent product thinking
- **[Ghostty](https://ghostty.org/)**: the bar for fast, high-quality terminal experiences
- **[xterm.js](https://xtermjs.org/)**: ecosystem reference for terminal compatibility
- **[Flutter](https://flutter.dev/)**: the foundation that makes Alera's cross-platform desktop UI possible
- **[Drift](https://drift.simonbinder.eu/)** and **[desktop_updater](https://pub.dev/packages/desktop_updater)**: used for local persistence and desktop update plumbing

---

## Developing

Want to contribute or hack on Alera locally? Start with:

- [`AGENTS.md`](AGENTS.md): contributor and agent governance rules
- [`docs/architecture.md`](docs/architecture.md): architecture glossary and naming rules
- [`docs/release-trust.md`](docs/release-trust.md): release signing, Linux package trust, and update manifest verification
- [`docs/testing.md`](docs/testing.md): unit, widget, golden, E2E, and coverage workflow
- [`docs/ui-styleguide.md`](docs/ui-styleguide.md): design tokens and UI rules

### Project layout

- `lib/src/app`: bootstrap, dependency providers, theme setup
- `lib/src/shared`: shared infrastructure (process, storage, helpers)
- `lib/src/features/projects`: project registry and project sidebar UI
- `lib/src/features/workbench`: workspaces, tabs, split layouts, terminal runtime
- `lib/src/features/agent_status`: agent lifecycle hooks and activity tracking
- `lib/src/features/updater`: update archive parsing and desktop updater integration
- `lib/src/features/shell`: top-level application shell
- `lib/src/design_system`: shared Alera UI components

### Checks

```bash
flutter analyze
flutter test --coverage --exclude-tags golden
dart run tool/quality/coverage_report.dart --input coverage/lcov.info --min-lines 100 --worst 25
```

Use `flutter test --tags golden` for visual regression tests and `flutter test integration_test -d macos` for local desktop E2E smoke coverage. See [`docs/testing.md`](docs/testing.md).

### Desktop flavors

Alera builds in two flavors selected by `ALERA_FLAVOR`:

| Flavor    | Bundle ID                  | Display name | Notes                                            |
|-----------|----------------------------|--------------|--------------------------------------------------|
| `dev`     | `dev.leynier.alera.dev`    | Alera Dev    | Default for local builds. Auto-update disabled.  |
| `release` | `dev.leynier.alera`        | Alera        | Used by CI and public release artifacts.         |

See [`lib/src/core/build_flavor.dart`](lib/src/core/build_flavor.dart) for the canonical strings.

---

## Releases and updates

Public release cuts are maintainer-managed through GitHub Actions. Release artifacts are signed or packaged for platform trust, and the public update indexes are Ed25519-signed schema v2 manifests with SHA-256 metadata for each artifact. Stable automatic installation stays disabled unless the release build embeds the manifest public key and the platform apply path explicitly allows the artifact type. Stable Linux updates are installed through signed package repositories; release-candidate Linux builds remain manual downloads.

- Stable manifest: `https://updates.alera.build/app-archive.json`
- Release-candidate manifest: `https://updates.alera.build/app-archive-rc.json`
- Updater payloads are hosted in Cloudflare R2 under `updates/stable/` and `updates/rc/`
- Stable Linux repositories are hosted in Cloudflare R2 under `linux/apt/` and `linux/rpm/`
- [GitHub Releases](https://github.com/leynier/alera/releases) remain the manual download surface

---

## Community & support

- ⭐ **Star this repo** to follow along. Alera ships often
- 🐛 **Found a bug or want a feature?** [Open an issue](https://github.com/leynier/alera/issues)
- 🌐 **Website:** [alera.build](https://alera.build)
- 📜 **License:** see [`LICENSE`](LICENSE)
- 🛡️ **Security:** see [`SECURITY.md`](SECURITY.md)
- 🤝 **Code of conduct:** see [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)

---

## Reference projects

Reference projects live under [`reference_projects/`](reference_projects/) and are **non-runtime** references for agentic development and orchestration patterns. Alera remains terminal-first and does not depend on any reference project at runtime.

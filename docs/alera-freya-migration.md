# Alera desktop Freya migration

This document tracks the incremental migration of the desktop client from GPUI to Freya. Flutter remains the production reference client and GPUI remains available as a fallback while parity work continues.

## Current implementation

- `rust/alera-desktop-core` contains framework-neutral runtime bridge access, workbench models, split mutations, persistence adapters, and the terminal emulator model.
- `experiments/alera-gpui` consumes the shared model and bridge modules, so the GPUI experiment remains buildable while the UI migration proceeds.
- `experiments/alera-freya` is pinned to Freya `v0.5.0-rc.1` and provides a macOS/Linux/Windows-compatible shell, titlebar, sidebar, workspace rows, tooltips, context panels, runtime selector, explorer/search/source-control/branches previews, terminal surfaces, a timer-paced blinking cursor, IME-aware key handling, and a drag-and-drop docking adapter.
- Freya docking keeps the neutral Alera ratios and supports center reorder, cross-panel moves, directional split previews, empty-panel pruning, and cancellation cleanup.
- Tab context menus use the Freya context-menu primitives and expose `Change Title`, `Close`, `Close Others`, and `Close Tabs to the Right`. Every close path detects unsaved editor content and requires an explicit destructive discard before it removes the runtime tab or collapses an empty split.
- Sidebar and context-panel content use Freya scroll views, including a visible vertical scrollbar for the right-side panel; workspace rows keep their local hover bounds, indentation, status dots, and icon tooltips.
- Explorer folders expand recursively through the runtime bridge with cached child listings, loading/error states, chevrons, and Flutter-compatible indentation. Opening a file creates or focuses one editor tab per normalized relative path, persists the tab as an editor kind, and renders it through `freya-code-editor` with a dark theme, line gutter, syntax colors, and scrollback.
- File-backed tabs now preserve Flutter's kinds and preview rules: Markdown opens as `markdownViewer`, raster images remain editor-kind tabs rendered from `workspacePreview.image`, and restored Merman preview tabs render the SVG returned by `workspacePreview.mermaid`. The UI does not bypass the runtime boundary to read local files.
- Explorer, Search, Source Control, and preview headers use the complete embedded VS Code Material Icon Theme manifest and SVG catalog used by Flutter, including filename-specific and expanded-folder variants rather than generic file glyphs.
- Explorer now uses only runtime-backed rows and exposes create file, create folder, rename, copy, cut, paste, duplicate, refresh, delete-to-trash, path copy, and Source Control root actions. Loading, empty, and error states no longer substitute demonstration files.
- Explorer rename and cut/paste moves retarget open editor and working-tree diff tabs, preserve a mounted editor's in-memory session by its runtime tab identity, update persisted tab payloads, and move a focused Source Control root with its directory.
- Editor saves now preserve the runtime content token, surface external-change conflicts, and require explicit confirmation before overwriting a file changed on disk.
- Source Control and Search no longer substitute demonstration changes or result rows. Source Control includes live branch state, mutations, history, scoped roots, working-tree and commit diff tabs. Search includes debounced runtime queries, list and directory-tree views, per-node and collapse-all state, replacement previews, per-match/file/all replacement, dirty-editor protection, content-token conflict protection, and clean-editor reloads after replacement.
- Pull Request uses the shared Forge service for GitHub authentication, create and draft flows, linking by number or URL, metadata, checks, comments, editing, ready/draft changes, close, unlink, and merge, squash, or rebase confirmation flows.
- Quotas, Resources, and Runtime status controls now share a delayed-hover and click-to-pin popover interaction. An external click closes the active popover, and every fixed-width status popover is anchored to its trailing edge so it remains inside the window.

## Commands

```text
make freya-debug
make freya-release
make freya-test
```

`make gpui-debug` and `make app-debug` remain unchanged. The Freya macOS launcher assigns the independent bundle id `dev.leynier.alera.freya.dev` for the dev flavor and stops an existing Freya process before launching a new one.

## Validation gate

Every UI phase is checked against one Flutter window and one Freya window with Computer Use. Each scenario refreshes the accessibility tree after every action, uses a double click on the titlebar for the full-size comparison, and records screenshots for the Flutter and Freya states. The current comparison captures were sent to Telegram during the release validation.

The code and headless gates currently pass:

- `cargo fmt --check --manifest-path experiments/alera-freya/Cargo.toml`
- `cargo clippy --manifest-path experiments/alera-freya/Cargo.toml --all-targets -- -D warnings`
- `make freya-test` (35 Freya tests plus 18 shared desktop-core tests)
- `cargo test --workspace --manifest-path rust/Cargo.toml`
- `dart analyze tool/debug/alera_debug.dart`
- `make freya-release`

The macOS release process was also profiled after opening a real workspace and terminal. Removing self-reactive side effects and replacing the continuous cursor animation with a 550 ms visibility timer reduced the observed idle load from about 25% CPU to 2.7%, while the physical footprint remained stable at about 137 MB instead of growing without bound.

## Not yet a cutover

The migration is intentionally not marked complete. Full feature parity still requires Explorer drag/drop, final Search visual/icon parity, Pull Request AI generation and expanded check details, the remaining runtime-backed settings and scroll geometry, service-backed quotas/resources/runtime data, agents and provider states, mobile/orchestration/diagnostics screens, complete keyboard and IME scenarios, and the final Flutter-versus-Freya golden screenshot matrix. Flutter remains the production client until those gaps are closed and the startup, memory, and streaming-performance budgets are measured on all target platforms.

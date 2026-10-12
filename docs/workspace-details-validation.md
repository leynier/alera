# Workspace Details Validation

## Implemented Behavior

The card follows the active workspace and shows its current PR immediately after successful creation. Other members of the existing stack expand in layer order without duplicating the current PR. Selecting a member reveals it in the existing Pull Request panel; browser opening remains a separate action. Tooltips include the full title, state, head/base and check summary. Check details reuse the existing lazy check list.

The primary PR action resolves conflicts first, then marks a permitted draft ready, fixes failed checks, and offers merge only after checks, mergeability, merge methods and account capabilities are confirmed. Unknown or failed capability requests block merge. The card and panel share confirmation dialogs. Stack confirmations list the affected PR numbers and titles. The controller reloads and compares the confirmed PR/head/base and affected stack before applying Merge or Ready. Fix and Resolve use the existing agent picker and defer to an existing watch handling the same concern.

Git progress reports the actual phase, elapsed seconds and bounded native command output. The Rust helper drains stdout/stderr concurrently and redacts authentication output. Local FRB streams and additive remote RPC use the same core implementation. Remote records are scoped by workspace, checkout and unique operation id, bounded in number and expired after completion. Old runtimes retain phase/duration and the existing network operations. Successful results clear after ten seconds; errors and explicit continuations remain available. Late output cannot replace a newer operation or a completed result.

Commit, push and PR creation have separate checkpoints. Continuations do not repeat completed stages. A successfully created PR remains visible if saving its local workspace link fails; this failure does not become another Create PR request.

Full, compact and essential densities retain scrolling and keyboard access. Essential density moves Host and Open In to Workspace Options. The terminal dimensions and existing toolbar/search behavior remain unchanged by showing the card. Workspaces retain their visibility and comparison preferences.

## Observed Validation

- Regenerated FRB and Dart bindings; normalized generated EOFs and formatted the affected sources.
- `flutter analyze`: no issues.
- `flutter build linux --debug`: successful full app build.
- Core Rust library: 180 tests passed, including working-tree comparisons and selective commits.
- Core Clippy with warnings denied: passed.
- Existing workspace Git RPC tests: 10 passed. New progress RPC test passed using a real temporary checkout and bare remote, including operation-id replay rejection and workspace/path isolation.
- Final focused Flutter regression batch: 80 tests passed across PR controls, agent actions, stack confirmation, panel behavior, reviewed submissions, account capability mapping, progress lifecycle and remote fallback/disconnection. Additional focused card/stack batch: 34 passed; these batches overlap and must not be summed as unique tests.
- Landing fidelity and keyboard registry: 19 tests passed; TypeScript checks passed.
- Windows: 40 integrated Flutter tests passed using the application sources, covering the action resolver, PR creation, partial-stage continuations, progress lifecycle, remote fallback/disconnection, PR/stack rows, small windows, focus, dimensions and the popup. This is a widget-test result, not a Windows desktop app build or live forge/network proof.
- Presentational Flutter previews passed on Linux, the physical Mac and the physical Windows machine. The screenshots use fixture data; macOS and Windows previews used an isolated presentational harness.
- `git diff --check`: clean.

## Remaining Platform Gate

Integrated macOS widget tests were attempted in the isolated source mirror and failed before test execution in the existing Ghostty native-assets hook: Zig 0.17 reports `unrecognized argument: --global-cache-dir`. The Mac has only Zig 0.17 installed. The widget implementation did not change that vendored hook or install another system toolchain. A compatible Ghostty/Zig toolchain is needed to finish integrated macOS validation and a full macOS app build. A full Windows desktop app build remains unverified; its integrated widget tests and physical presentational preview passed.

Real hosting-provider mutations and a live hub/satellite transfer were not performed. Account capability mapping, API command construction, host routing, protocol fallback and the shared Git engine were verified through focused fixtures and temporary repositories.

## UI Polish Follow-Up

Claude Opus 5.5 with High effort refined the presentation against T3 Code: aligned icon/text columns, split primary/menu targets, tighter sections, PR metadata/action pills, semantic check icons, keyboard focus rings, stable disabled menu widths and a host-labelled essential row. The parent reviewed the edits and fixed a minimum-width pending state where the PR state label was squeezed to a few pixels. Checks now use the remaining space and retain their full tooltip while the state and pending action stay readable.

The UI follow-up passed clean analysis, a refreshed full Linux debug build, 24 focused widget/preview tests and 23 landing fidelity/shortcut/storyboard tests with TypeScript checks. Browser inspection confirmed the landing card renders without row overflow at desktop width and the 375 px page has no horizontal overflow. Updated Flutter fixture captures are in `/tmp/alera-workspace-details-ui-polish/`. These are Linux renders with platform labels, not refreshed physical macOS/Windows captures. The existing macOS toolchain gate and unverified full Windows desktop build still apply.

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

## Naming

- Do not create vague modules named `helpers`, `utils`, `common`, `misc`, or similar dumping grounds.
- Name files and types after the domain concept they model, such as `workspace_folder_opener.dart` or `update_archive.dart`.
- If a file name starts feeling generic, split responsibilities before adding more code.

## Flutter UI Rules

- Flutter UI values MUST come from `AleraTokens` and `ThemeData`.
- New UI code MUST NOT introduce ad-hoc visual literals for color, spacing, radius, duration, or typography when an existing token/theme value covers the role.
- `Colors.transparent` MAY be used only for explicit transparent states.
- Visible UI copy MUST use sentence case.
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
- `test/AGENTS.md` applies under `test/`.
- `.github/AGENTS.md` applies under `.github/`.
- `tool/release/AGENTS.md` applies under `tool/release/`.

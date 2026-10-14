# Alera UI Style Guide

## Source Of Truth

Flutter UI values come from:

- `lib/src/app/theme/alera_tokens.dart`
- `lib/src/app/theme/alera_dark_theme.dart`
- `ThemeData` and Material component themes derived from those tokens

Do not hardcode colors, spacing, radii, durations, typography, shadows, or component shapes when an existing token/theme value covers the role.

## Visual Direction

Alera is a terminal-first desktop ADE. The UI should stay quiet, dense, and work-focused so terminals, workspaces, and agent processes remain the primary surface.

- Keep the palette grayscale-first with neutral accent emphasis.
- Use status colors only for actual status semantics.
- Keep dark mode as the only active app theme in this version.
- Use Inter for general UI text and JetBrains Mono for terminal/code-adjacent text.

## Token Baseline

Spacing:

| Token | Value |
| --- | --- |
| `space2` | `2.0` |
| `space4` | `4.0` |
| `space6` | `6.0` |
| `space8` | `8.0` |
| `space12` | `12.0` |
| `space16` | `16.0` |
| `space20` | `20.0` |
| `space24` | `24.0` |
| `space32` | `32.0` |
| `space48` | `48.0` |

Radius:

| Token | Value | Intended usage |
| --- | --- | --- |
| `radiusXs` | `4.0` | Tiny inline elements under about 18px tall: keycaps, checkboxes, stepper buttons, drop indicators, tray hit areas |
| `radiusSm` | `6.0` | Chips, badges, tooltips, tab chips, compact controls |
| `radiusMd` | `8.0` | Standard inputs and controls |
| `radiusLg` | `8.0` | Buttons (theme default), cards, panels, grouped containers |
| `radiusXl` | `12.0` | Dialogs and large elevated containers |
| `radiusPill` | `20.0` | Real pills only: floating pill buttons, toggle tracks, round dictation control |

`radiusMd` and `radiusLg` share a value, so a rounded surface nested inside another no longer gets a smaller radius for free. Keep the inner radius at or below the outer radius minus the padding between them: menu item highlights inside a popup use `radiusSm`, and a close button inside a tab chip uses `radiusXs`.

Selection and status:

| Token | Value | Usage |
| --- | --- | --- |
| `activeRailWidth` | `2.0` | Width of the accent rail `AleraActiveRail` draws on the selected row |
| `statusTintAlpha` | `0.14` | Alpha of the tone color behind a tinted `AleraBadge` label |

Core colors:

| Token | Semantic usage |
| --- | --- |
| `bg` | Global background |
| `surface` | Base container surfaces |
| `surfaceVariant` | Emphasized neutral containers |
| `surfaceElevated` | Hover/elevated neutral surfaces |
| `border` | Standard control/container border |
| `borderSubtle` | Subtle separators and low-emphasis borders |
| `accent` | Active emphasis and neutral highlight |
| `onAccent` | Foreground on accent backgrounds |
| `foreground` | High-emphasis text/icons |
| `foregroundMuted` | Medium-emphasis text/icons |
| `foregroundFaint` | Low-emphasis text/icons |
| `success` | Positive status |
| `warning` | Warning status |
| `info` | Informational status |
| `done` | Merged or completed-for-review status |
| `error` | Error and destructive emphasis |
| `onError` | Foreground on error backgrounds |
| `shadowSoft` | Soft menu/list overlays and subtle elevated shadows |
| `focusRing` | Keyboard focus outline on custom tappable surfaces such as `HoverContainer` |

Motion:

| Token | Value |
| --- | --- |
| `durationFast` | `100ms` |
| `durationMid` | `180ms` |
| `durationSlow` | `280ms` |
| `durationSpin` | `1200ms` (full turn of continuously rotating progress indicators) |
| `toastDuration` | `4000ms` (default toast lifetime) |
| `toastLongDuration` | `6000ms` (warnings and errors worth reading; also `AleraToast.longDuration`) |

Typography and sizing:

| Token | Usage |
| --- | --- |
| `statusBarTextStyle` | Labels in the bottom status bar (mono, 10px), with `iconStatusBar` (13px) and `iconStatusBarSm` (11px) beside them |
| `monoMicroStyle`, `monoCaptionFaintStyle` | Dense mono values (10px) and faint mono captions (9px) in hover cards and panels |
| `logoSm`, `logoMd`, `logoLg` | `AleraLogo` sizes for the sidebar brand row, loading screens, and About dialog |
| `iconButtonXs`, `iconButtonSm` | Hit areas for compact `AleraIconButton`s inside chips and row headers |
| `conversationMaxWidth` | Content width of the home composer and other centered conversations |
| `controlHeight` | Height of compact single-line controls (`AleraDropdownField`, `AleraCompactInput`, the date button of `AleraDateTimeField`) so they line up in one row |
| `keyValueLabelWidth` | Width of the muted label column in `AleraKeyValueRow` |
| `keyValueListLabelWidth`, `keyValueStackBreakpoint` | Label column of `AleraKeyValueList` and the width under which it stacks labels above values |
| `railWidth`, `railCompactWidth` | `AleraRail` width with labels (72px) and icon-only (48px) |

## Component Rules

- Primary actions use `FilledButton`, `FilledButton.icon`, or `FilledButton.tonalIcon`.
- Secondary actions use `TextButton` or `OutlinedButton`.
- Destructive primary actions use a filled style with `AleraTokens.error` and `AleraTokens.onError`.
- Inline micro-actions may use `IconButton` or tokenized `InkWell` patterns.
- Tappable rows built on `HoverContainer` are keyboard reachable: Tab focuses them, Enter or Space activates them, and a `focusRing` outline shows while navigating by keyboard.
- Keyboard shortcuts render as `AleraKeybindingBadge` keycaps; hide the badge when an action has no binding instead of printing a placeholder.
- The selected item of a vertical list (sidebar workspace and agent rows, the Settings navigation, master-detail lists, the command palette and Quick Open highlight, picker rows with a current value) uses `AleraActiveRail`: the row background is `AleraActiveRail.selectedColor` (`accentSubtle`, a translucent accent that reads on any container; `surfaceElevated` sits too close to the sidebar and panel chrome) and a 2px `accent` rail sits at the leading edge, inset by `space6` vertically, drawn over the row so selecting it never shifts the layout. Hover stays on the existing hover color, and the keyboard `focusRing` stays separate from selection.
- Horizontal strips (tab chips, segmented controls) never get a rail: the active chip uses `surfaceElevated` with accent or foreground text and icon.
- Status labels use `AleraBadge` with an `AleraBadgeTone`: `neutral`, `accent`, `attention` (warning), `success`, `error`, `info`, `done`. A toned badge draws its Title Case label in the tone color at `labelSmall` w600 on the tone color at `statusTintAlpha`, with `radiusSm` corners; `neutral` and `accent` keep the `accentSubtle` fill. Use tones only for status semantics; tags and counts stay `neutral`.
- Agent status in sidebar rows: a working run keeps its spinner and gets no label, waiting shows `Needs Input` (attention), blocked shows `Blocked` (error), and done shows `Done` (success). An interrupted run keeps its cancel glyph. While a badge names the state, the leading status slot shows a muted dot so the color is not repeated. At narrow widths the badge outranks the agent glyph and inline metadata trays.
- Loading and empty lists share `AleraEmptyState` (`loading: true` shows a small spinner in its icon slot).
- Multi-step work (installs, setup pipelines) uses `AleraProgressSteps`: one row per stage with a 14px glyph joined by a `borderSubtle` connector. Pending shows a faint circle, active an `accent` spinner (`strokeSm`) with an optional progress bar, done a muted check, failed an `error` glyph with the reason as detail, and skipped a faint cancel glyph.
- A toast with an action (`actionLabel`/`onAction` on `AleraToast.show`) is the only toast that takes pointer input; pressing the action also dismisses it.
- Default Material button shape uses `radiusLg`.
- Default Material button minimum height is `34`.
- Confirmation dialogs use equal-width secondary and primary footer actions.
- Prompt-first forms put each property in an `AleraPropertyChip` that opens an `AleraPopover`. The chip marks an open popover as active, a blocking value with the error border, and a value seeded from where the form was opened with a `From Context` badge. A popover closes on Escape or an outside tap and returns focus to where it was; a search-and-sections choice inside it uses `AleraSectionedPicker`.
- Durations are edited as a number plus unit with `AleraDurationField` and printed with `aleraDurationLabel`; times of day are typed into `AleraTimeOfDayField` (24-hour display, accepts `9`, `9:30`, `6:05 pm`). Fields report raw values and leave range checks and their messages to the caller.

## Surface Model

Desktop workspaces start with a chrome-less primary terminal in the center. Tabs dragged from the right panel land in the center with the same drop zones as pane splits. The tab strip appears when the center has more than one tab and hides again at one. The workspace row mixes with the center agent while only one agent runs there; two or more center agents nest as sibling rows. Right-panel agents stay extra child rows and do not change that count. Settings > Application > Desktop > New Workspace Tools picks which Explorer, Search, Source Control, and Pull Request tabs open, and in what order, for workspaces created after that. Existing workspaces keep their own panel. An empty selection keeps a new panel empty until the user adds a tool.

The right panel is a splitable tab workbench for auxiliary terminals, files, previews, diffs, and Explorer, Search, Source Control, and Pull Request tools. Those tools are tabs in that tree: each exists at most once, can sit beside any other tab, and can be split or dragged like a terminal. Files opened from a tab or tool stay in that panel; Mod+click opens a preview in the other panel (center vs right). The Add Tab menu also offers Terminal and any Agent Profiles marked to appear next to New Terminal. Choosing a profile from that menu opens a prompt dialog first, with dictation, file attachments, and Skip to launch without a prompt. An empty panel offers the same tools and Terminal, plus a single Agents entry. Agents opens the existing profile picker with Agent Profiles only, then the same prompt dialog. Each workspace retains its own pane tree, order, and selection in desktop view preferences. Hiding the panel preserves its tabs and returns terminal focus to the primary.

Requested panel width is stored per workspace, constrained at render time to leave the center minimum available. Pane splits stay in view prefs. Inactive terminal surfaces are unmounted and hold no visibility lease.

- Surface layering should follow `bg` -> `surface` -> `surfaceVariant` -> `surfaceElevated`.
- Container borders should use `border` or `borderSubtle` based on emphasis.
- Card-like surfaces should use tokenized radii, typically `radiusLg`.
- New or touched UI must migrate nearby non-token outliers when an equivalent token exists.

## Copy And State

- Actions, buttons, menus, dropdowns, labels, and other controls use title case. Descriptions, explanations, helper text, status messages, errors, notifications, and other prose use sentence case, preserving proper nouns, product names, acronyms, and technical identifiers.
- UI copy must not overclaim. Do not imply an action succeeded, skipped, verified, deleted, or protected something unless code has the result state.
- For long-running actions, reserve control width up front when labels/icons can change.
- Loading and progress copy ends with the ellipsis character (`Loading…`), never three periods.
- Prefer disabled state for short work and stage labels/progress for multi-step work.

## Iconography

Icons come from Lucide (`lucide_icons_flutter`), the same family Orca uses and the de-facto standard for modern developer tooling. Reference icons by semantic role through `AleraIcons` (e.g. `AleraIcons.delete`, `AleraIcons.gitBranch`), never raw `Icons.*` or `LucideIcons.*` at call sites.

- `AleraIcons` (`lib/src/design_system/icons/alera_icons.dart`) is the single source of truth and the only entry point to `lucide_icons_flutter`. Add a new semantic role there rather than reaching for a glyph at the call site.
- File-type icons in the explorer keep using `vscode_material_icon_theme` (the VSCode standard for file trees) via `AleraFileIcon`; its fallbacks resolve through `AleraIcons`. The mobile app draws the same glyphs in Explorer, Source Control, Search, Quick Open, and the file and diff viewers through its own copy of `AleraFileIcon` (`mobile/lib/src/design_system/icons/alera_file_icon.dart`), pinned to the same package version.

## Reference Paths

| Area | Reference paths |
| --- | --- |
| Tokens and theme | `lib/src/app/theme/alera_tokens.dart`, `lib/src/app/theme/alera_dark_theme.dart` |
| Iconography | `lib/src/design_system/icons/alera_icons.dart`, `lib/src/design_system/icons/alera_file_icon.dart` |
| Primary/secondary buttons | `lib/src/features/shell/presentation/alera_shell_page.dart`, `lib/src/features/workbench/presentation/project_workbench_sidebar.dart`, `lib/src/features/workbench/presentation/create_workspace_dialog.dart` |
| Inline micro-actions | `lib/src/design_system/buttons/alera_icon_button.dart`, `lib/src/features/workbench/presentation/project_workbench_sidebar.dart` |
| Status colors | `lib/src/design_system/feedback/alera_status_dot.dart`, `lib/src/features/workbench/presentation/terminal_surface.dart` |
| Component library | `lib/src/design_system/` |

## Component Library

Shared, reusable UI lives in `lib/src/design_system/`, grouped by role and prefixed `Alera`. Build new screens by composing these before writing ad-hoc widgets; only add a new component when no existing one fits, and add it here with a preview.

Components are **presentational**: they take data and callbacks as parameters and must not read Riverpod providers or touch native (`dart:io`/`dart:ffi`) code. When a feature widget needs provider state, keep the design-system component pure and wire the provider in a thin wrapper inside the feature.

| Role | Components |
| --- | --- |
| Buttons | `AleraIconButton`, `AleraSegmentedButton`, `AleraTabStrip` (underlined page tabs with an optional muted count) |
| Badges & chips | `AleraBadge`, `AleraKeybindingBadge`, `AleraChip`, `AleraPropertyChip`, `AleraAttentionChip` (status-bar icon and count, capped at `999+`, in a warning, accent, or muted tone) |
| Surfaces | `AleraPanel`, `AleraCommandLine`, `HoverContainer`, `AleraActiveRail`, `AleraPopover` |
| Feedback | `AleraStatusDot`, `AleraStatusIndicator`, `AleraColorSwatch`, `AleraEmptyState`, `AleraInlineNotice`, `AleraToast` (optional `actionLabel`/`onAction`), `AleraQrCode`, `AleraProgressSteps`, `AleraGateCard` (a decision a run owes a person: prompt, evidence links, notes, answers, stale and busy states), `AleraShimmerText` (a paced highlight sweep for work in progress; animates only under an `AleraShimmerScope`) |
| Forms | `AleraTextField`, `AleraSearchField`, `AleraNumberField`, `AleraSettingRow`, `AleraDropdownField` (optional `group` headers and `detail` notes per entry), `AleraSegmentedChoice` (two or three options with the selected option's helper text and each disabled option's reason), `AleraCheckbox`, `AleraCompactInput`, `AleraDurationField`, `AleraTimeOfDayField`, `AleraDateTimeField` |
| Chat | `AleraMessageBubble` (outgoing or incoming message with heading, status badge, New marker, and time) |
| Markdown | `AleraMarkdownView` (read-only Markdown; callers own selection, links, images and code rendering), `AleraCodeBlock` (language header, hover Copy, optional highlighted span, horizontal scroll that leaves the mouse wheel to the enclosing list) |
| Lists | `AleraActivityRow` (optional `trailing` note), `AleraTimeline` (lazy day-grouped event log with open markers), `AleraKeyValueList` (selectable labelled facts with optional Copy) |
| Layout | `AleraSectionHeader`, `AleraDialog`, `AleraDialogHeader`, `AleraConfirmDialog`, `AleraSettingsGroup` (optional `collapsible`, `initiallyExpanded`, `trailing`), `AleraMasterDetail`, `AleraHorizontalScrollView`, `AleraRail` (vertical section rail with icon, label, and count badge; icon-only with tooltips when compact), `AleraSectionedPicker`, `AleraCollapsibleSection`, `AleraKeyValueRow` |
| Menus | `AleraDropdownEntry`, `AleraMenuItem` |
| Iconography | `AleraIcons`, `AleraFileIcon`, `AleraLogo` |

## Widget Previews

Every component ships a co-located `*.preview.dart` file so it can be developed and reviewed in isolation, plus an aggregate view in `lib/src/design_system/gallery/`.

- Annotate preview functions with `@AleraPreview` (from `lib/src/design_system/alera_preview.dart`), which applies the Alera dark theme and ambient scaffolding automatically. Do not use the bare `@Preview`.
- A preview function must be public and return a `Widget` or `WidgetBuilder`; its arguments and callbacks must be `const`/static.
- Launch the previewer with `flutter widget-preview start <absolute-project-path>` (the repository root for desktop, or its `mobile` directory). Passing an absolute path also keeps Flutter 3.47's scaffold restart anchored to the application when a pubspec changes. Previews render on Flutter Web, so they cover UI only - terminal runtime, updater, and other native code paths are not previewable and stay out of the design system. Quota previews use the presentational content; the application wrapper supplies its runtime actions.
- The checked-in `.widget_preview/pubspec_overrides.yaml` files preserve the app's terminal forks in generated preview scaffolds. After `flutter widget-preview clean`, restore that file with `git restore -- .widget_preview/pubspec_overrides.yaml` from the corresponding application directory before starting again.

## Workspace Details

The central workbench overlays the workspace details card in its upper-right corner without resizing terminal content. It is initially visible when the central pane meets `wideContentBreakpoint` and the minimum available height. Visibility persists per workspace. Smaller panes and an open terminal search use a closed-by-default popover; its contents scroll in short windows. Toggle Workspace Details is part of the movable terminal toolbar and is registered in the command registry without a default shortcut. Surfaces without a terminal retain an overlay toggle. With the terminal toolbar in the top right corner, the card sits just below it, also when the panel shows a tab strip because it holds more than one tab; with the toolbar in another corner the card sits near the top edge, below the tab strip when one is shown, so it never covers the strip's controls. The position derives from the panel state and the toolbar corner setting, not from measuring the toolbar. Row menus open under the row that was clicked, with an icon per entry; the Git action menu groups commit actions, then push actions, then Pull. Changes counts the uncommitted lines of the files Source Control lists, opens Source Control in the right panel, or selects it wherever it is already open, and retains its label and last counts during background refreshes.

`AleraWorkspaceDetailsCard` is presentational and has a co-located widget preview. An Agents section between the workspace and Git sections lists the agents running in the workspace's awake terminals, in tab order, with their identity icon, tab title or agent name, latest activity, and state badge or spinner; clicking one focuses its tab. Full density shows four agents and compact three, hiding the rest behind a toggle, and essential density folds them into one row led by the most urgent agent with a menu of all of them. Workspaces without agents show no section. A linked issue adds a workspace row below Open In with its state icon, reference and title, and state; clicking it opens the issue and its menu opens, changes, or unlinks it. Without an issue, the host menu offers Link Issue when the host supports links, and essential density lists the issue in the workspace options menu. The Branch row shows commits ahead of and behind its upstream with arrow counts, or Unpublished when the branch has no upstream; the counts come from the last fetch, which the Branch menu can run. A workspace with a parent or children adds a row naming its parent and child count: clicking it opens the parent, and its menu opens the parent or any active child. Essential density lists the related workspaces in the options menu. The host menu carries the workspace actions of the sidebar row menu: Hand Off or Hand On, Rename, Link Issue, Sleep, Archive or Unarchive, and Remove, through the same flows and confirmations. Sleep and archive report their result through a published toast, since sleeping the open workspace closes the card. A workspace with live automations adds a row naming the automation or their count with the latest run in its status tone, preferring a run still in progress over finished ones; clicking it opens Automations scoped to the workspace, and its menu opens one automation, the scoped list, or New Automation Here, which the host menu also offers. Completed and trashed automations stay off the card. Essential density lists them in the workspace options menu. Host, Open In, Branch, Git action and Changes rows use the existing Inter typography, semantic icons and surface tokens. Added and removed counts use success and error tokens. Provider reads, host routing, preferences and dialog launchers live in the feature wrapper. Opening the card preserves pane focus; closing restores pane focus only when the details controls owned it.

Git submission review and its per-file patches share an immutable merge-base-to-working-tree snapshot, including new files. The comparison base shown under the Branch row resolves from the workspace/repository preference, an open review, the workspace source branch and the repository default branch, preferring available remote references. An invalid explicit base displays an error and can be reset to Automatic from the Branch control.

Git submission reviews whole files and editable commit text before writing. AI Assist receives only selected snapshot patches. Canceling or generating text does not stage files. Selective commits validate HEAD, disk content and the index, preserve excluded staged files, and commit the complete selected files. Background jobs retain their original workspace and host; completed commit and push stages survive an explicit retry after a later failure. Remote folders cannot be opened in the local file manager; copying their path and opening the repository URL remain available.

The current workspace PR appears directly after the branch, including its number, full-title tooltip, state, check summary and contextual action. The existing stack expands beneath it in layer order; selecting a member reveals it in the Pull Request panel without changing the workspace's linked PR. Checks open the existing lazy details list. Merge and Ready share confirmation launchers with the panel and revalidate the PR identity, head, checks and account capabilities after confirmation. Unknown capabilities never enable merge.

Full, compact and essential densities depend on the available height. Compact removes secondary row descriptions; essential moves Host and Open In into Workspace Options. PRs, Git progress and Changes remain reachable and the card scrolls when needed. Network progress carries bounded, credential-redacted output from the host executing Git. Older runtimes retain phase and elapsed time. Successful results stay for ten seconds; failures retain the completed-stage summary and an explicit continuation action.

Workspace detail rows share a fixed icon slot and text column, with a primary action and chevron separated by a hairline. Hover tints the row and selected segment; keyboard focus uses the focus-ring token. The PR state, checks and contextual action sit beneath its title in the same text column. Essential density keeps the host visible in the Workspace Options row. At the minimum card width, checks may ellipsize while the PR state and pending action remain readable; their complete label is available in the tooltip.

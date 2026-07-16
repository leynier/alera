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
| `radiusSm` | `4.0` | Small chips, inline toggles, compact controls |
| `radiusMd` | `6.0` | Standard inputs and controls |
| `radiusLg` | `10.0` | Cards, panels, grouped containers |
| `radiusXl` | `12.0` | Dialogs and large elevated containers |
| `radiusPill` | `20.0` | Pills and badge-like separators |

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
| `error` | Error and destructive emphasis |
| `onError` | Foreground on error backgrounds |
| `shadowSoft` | Soft menu/list overlays and subtle elevated shadows |

Motion:

| Token | Value |
| --- | --- |
| `durationFast` | `100ms` |
| `durationMid` | `180ms` |
| `durationSlow` | `280ms` |
| `durationSpin` | `1200ms` (full turn of continuously rotating progress indicators) |

## Component Rules

- Primary actions use `FilledButton`, `FilledButton.icon`, or `FilledButton.tonalIcon`.
- Secondary actions use `TextButton` or `OutlinedButton`.
- Destructive primary actions use a filled style with `AleraTokens.error` and `AleraTokens.onError`.
- Inline micro-actions may use `IconButton` or tokenized `InkWell` patterns.
- Default Material button shape uses `radiusLg`.
- Default Material button minimum height is `34`.
- Confirmation dialogs use equal-width secondary and primary footer actions.

## Surface Model

- Surface layering should follow `bg` -> `surface` -> `surfaceVariant` -> `surfaceElevated`.
- Container borders should use `border` or `borderSubtle` based on emphasis.
- Card-like surfaces should use tokenized radii, typically `radiusLg` or `radiusMd`.
- New or touched UI must migrate nearby non-token outliers when an equivalent token exists.

## Copy And State

- Visible UI copy must use title case (e.g., "New Workspace", "AI Text").
- UI copy must not overclaim. Do not imply an action succeeded, skipped, verified, deleted, or protected something unless code has the result state.
- For long-running actions, reserve control width up front when labels/icons can change.
- Prefer disabled state for short work and stage labels/progress for multi-step work.

## Iconography

Icons come from Lucide (`lucide_icons_flutter`), the same family Orca uses and the de-facto standard for modern developer tooling. Reference icons by semantic role through `AleraIcons` (e.g. `AleraIcons.delete`, `AleraIcons.gitBranch`), never raw `Icons.*` or `LucideIcons.*` at call sites.

- `AleraIcons` (`lib/src/design_system/icons/alera_icons.dart`) is the single source of truth and the only entry point to `lucide_icons_flutter`. Add a new semantic role there rather than reaching for a glyph at the call site.
- File-type icons in the explorer keep using `vscode_material_icon_theme` (the VSCode standard for file trees) via `AleraFileIcon`; its fallbacks resolve through `AleraIcons`.

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
| Buttons | `AleraIconButton`, `AleraSegmentedButton` |
| Badges & chips | `AleraBadge`, `AleraChip` |
| Surfaces | `AleraPanel`, `HoverContainer` |
| Feedback | `AleraStatusDot`, `AleraStatusIndicator`, `AleraColorSwatch`, `AleraEmptyState`, `AleraToast` |
| Forms | `AleraTextField`, `AleraSearchField`, `AleraNumberField`, `AleraSettingRow`, `AleraDropdownField`, `AleraCheckbox` |
| Layout | `AleraSectionHeader`, `AleraDialog`, `AleraDialogHeader`, `AleraConfirmDialog`, `AleraSettingsGroup`, `AleraMasterDetail` |
| Menus | `AleraDropdownEntry`, `AleraMenuItem` |
| Iconography | `AleraIcons`, `AleraFileIcon` |

## Widget Previews

Every component ships a co-located `*.preview.dart` file so it can be developed and reviewed in isolation, plus an aggregate view in `lib/src/design_system/gallery/`.

- Annotate preview functions with `@AleraPreview` (from `lib/src/design_system/alera_preview.dart`), which applies the Alera dark theme and ambient scaffolding automatically. Do not use the bare `@Preview`.
- A preview function must be public and return a `Widget` or `WidgetBuilder`; its arguments and callbacks must be `const`/static.
- Launch the previewer from the repo root with `flutter widget-preview start` (requires Chrome). Previews render on Flutter Web, so they cover UI only — terminal runtime, updater, and other native code paths are not previewable and stay out of the design system.

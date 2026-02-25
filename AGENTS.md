# AGENTS

## Scope
This file applies to the entire repository and defines contributor rules plus a design-system-first policy for Flutter UI work.

All guidance in this document is mandatory for active UI code. Existing UI outliers MUST be converged to this system during this initiative.

This document defines governance only. It does not change runtime APIs, schemas, or protocol types.

## Global Contribution Rules
- Commits and pull requests MUST be written in English unless the user explicitly requests another language.
- Commit and pull request titles MUST be lowercase and MUST follow Conventional Commits.
- This document SHALL remain organized with non-numbered section headers.

## Design System Source of Truth
- Flutter UI values MUST come from `AleraTokens` and `ThemeData`.
- New UI code MUST NOT introduce ad-hoc visual literals (color, spacing, radius, duration, typography) when an existing token/theme value already exists.
- `Colors.transparent` MAY be used only for explicit transparent states.
- Visible UI copy (texts, labels, tooltips, placeholders, and messages) MUST use sentence case.
- The active theme strategy SHALL remain dark-mode-only in this version.
- Typography MUST remain fixed to Inter for general text and JetBrains Mono for monospaced text.

## Tokens Baseline
The following baseline values are authoritative for new UI code.

### Spacing Scale
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

### Radius Scale
| Token | Value |
| --- | --- |
| `radiusSm` | `4.0` |
| `radiusMd` | `6.0` |
| `radiusLg` | `10.0` |
| `radiusXl` | `12.0` |
| `radiusPill` | `20.0` |

### Core Color Tokens
| Token | Hex |
| --- | --- |
| `bg` | `#101010` |
| `surface` | `#181818` |
| `surfaceVariant` | `#202020` |
| `surfaceElevated` | `#242424` |
| `border` | `#323232` |
| `borderSubtle` | `#272727` |
| `accent` | `#E0E0E0` |
| `accentSubtle` | `#1AE0E0E0` |
| `onAccent` | `#101010` |
| `foreground` | `#F5F5F5` |
| `foregroundMuted` | `#A1A1A1` |
| `foregroundFaint` | `#606060` |
| `success` | `#22C55E` |
| `error` | `#F87171` |
| `onError` | `#2C0D0D` |
| `warning` | `#F59E0B` |
| `shadowSoft` | `#14000000` |

### Motion Durations
| Token | Value |
| --- | --- |
| `durationFast` | `100ms` |
| `durationMid` | `180ms` |
| `durationSlow` | `280ms` |

### Theme Button Baseline
- The default Material button shape SHALL use `radiusLg`.
- The default Material button minimum height SHALL be `34`.

## Button Model (Primary, Secondary, Destructive, Inline)
- Primary actions MUST use `FilledButton`, `FilledButton.icon`, or `FilledButton.tonalIcon`.
- Secondary actions MUST use `TextButton` or `OutlinedButton`.
- Destructive primary actions MUST use a filled style with `AleraTokens.error` as background and `AleraTokens.onError` as foreground.
- Inline micro-actions MAY use `IconButton` or `InkWell` when compact interaction is required.
- There is no hard cap on the number of primary actions per surface in this version.

## Radius and Surface Model
- `radiusSm` SHOULD be used for compact controls, tags, and inline chips.
- `radiusMd` SHOULD be used for standard controls and form elements.
- `radiusLg` SHOULD be used for cards, list panels, and grouped containers.
- `radiusXl` SHOULD be used for large containers and dialogs.
- `radiusPill` SHOULD be reserved for pill-like badges/dividers.
- Surface layering SHOULD follow `bg` -> `surface` -> `surfaceVariant` -> `surfaceElevated`.
- Container borders SHOULD use `border` or `borderSubtle` based on emphasis.

## Color Role Model
- The system SHALL keep a grayscale-first palette with neutral accent emphasis.
- `accent` SHALL represent active emphasis and key neutral-highlight states.
- `foreground`, `foregroundMuted`, and `foregroundFaint` SHALL represent strong, medium, and low text emphasis.
- `success`, `error`, and `warning` SHALL represent status semantics.
- Destructive UI patterns SHALL use `error` and `onError` as the canonical pair.

## Design System Pattern Catalog (Section 7 Replacement)
This catalog is the implementation target for new UI work.

### Table A: Action Type -> Widget Pattern -> Visual Recipe
| Action Type | Approved Widget Pattern | Default Visual Recipe |
| --- | --- | --- |
| Primary | `FilledButton*` variants | Theme shape `radiusLg`, min height `34`, token-driven colors |
| Secondary | `TextButton` or `OutlinedButton` | Theme shape `radiusLg`, token-driven foreground/border |
| Destructive Primary | `FilledButton` (destructive style) | `bg=error`, `fg=onError`, token-only colors |
| Inline Micro | `IconButton` or `InkWell` | Compact hit area, token-based radius and colors |

### Table B: Radius Token -> Intended Usage
| Radius Token | Intended Usage |
| --- | --- |
| `radiusSm` | Small chips, inline toggles, compact controls |
| `radiusMd` | Standard button/input/control shapes |
| `radiusLg` | Cards, panels, timeline groups |
| `radiusXl` | Dialogs and larger elevated containers |
| `radiusPill` | Pills and rounded badge-like separators |

### Table C: Color Token -> Semantic Usage
| Color Token | Semantic Usage |
| --- | --- |
| `bg` | Global background |
| `surface` | Base container surfaces |
| `surfaceVariant` | Emphasized neutral container surfaces |
| `surfaceElevated` | Hover/elevated neutral surfaces |
| `border` | Standard control/container border |
| `borderSubtle` | Subtle separators and low-emphasis border |
| `accent` | Active emphasis and neutral highlight |
| `onAccent` | Foreground on accent backgrounds |
| `foreground` | High-emphasis text/icons |
| `foregroundMuted` | Medium-emphasis text/icons |
| `foregroundFaint` | Low-emphasis text/icons |
| `success` | Positive status |
| `warning` | Warning status |
| `error` | Error and destructive emphasis |
| `onError` | Foreground on error backgrounds |
| `shadowSoft` | Soft menu/list overlays and subtle elevated shadow |

### Table D: Current Reference Paths (Not Exhaustive)
| Area | Reference Paths |
| --- | --- |
| Tokens and theme baseline | `lib/src/app/theme/alera_tokens.dart`, `lib/src/app/theme/alera_dark_theme.dart` |
| Primary/secondary button examples | `lib/src/features/shell/presentation/alera_top_bar.dart`, `lib/src/features/shell/presentation/alera_shell_page.dart`, `lib/src/features/session/presentation/widgets/user_input_card.dart` |
| Inline micro-actions | `lib/src/features/session/presentation/widgets/composer.dart`, `lib/src/features/session/presentation/session_workspace_view.dart`, `lib/src/features/session/presentation/widgets/approval_card.dart` |
| Status and semantic color usage | `lib/src/features/shell/presentation/alera_status_bar.dart`, `lib/src/features/session/presentation/widgets/status_color.dart` |

### Conformance Scenarios
- Scenario: An agent adds a new destructive button.
  Expected: Uses `FilledButton` with `AleraTokens.error` and `AleraTokens.onError`.
- Scenario: An agent adds a secondary dismiss/cancel action.
  Expected: Uses `TextButton` or `OutlinedButton`, not a custom filled primary.
- Scenario: An agent adds a new card-like surface.
  Expected: Uses tokenized radii (typically `radiusLg` or `radiusMd`) and avoids ad-hoc radius values.
- Scenario: An existing widget contains an outlier color.
  Expected: MUST be migrated to token equivalents in this initiative.
- Scenario: A PR title is `Feat: Update UI`.
  Expected: Non-compliant because titles must be lowercase Conventional Commits.
- Scenario: New UI code introduces inline literal color when a token exists.
  Expected: Non-compliant with source-of-truth rules.

## Legacy Outliers (Convergence Required)
- Current outliers (for example direct orange/red/black-alpha literals) MUST be migrated to tokens in this initiative.
- Outliers are not deferred in this phase.
- New code and touched existing code MUST NOT copy or preserve non-token outlier patterns when equivalent tokenized patterns exist.

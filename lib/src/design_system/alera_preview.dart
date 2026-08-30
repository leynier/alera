import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds the Alera dark theme for widget previews. Must stay a public,
/// top-level function so it can be referenced as a `const` tear-off from the
/// [AleraPreview] annotation (the previewer rejects private or instance
/// callbacks).
PreviewThemeData aleraPreviewTheme() => const _AleraPreviewTheme();

final class _AleraPreviewTheme extends PreviewThemeData {
  const _AleraPreviewTheme();

  @override
  Widget apply(BuildContext context, Widget child) =>
      Theme(data: buildAleraDarkTheme(), child: child);
}

/// Wraps a previewed component in the same ambient scaffolding the real app
/// provides: a [ProviderScope] for Riverpod reads and the global background so
/// dark surfaces render against the right backdrop.
Widget aleraPreviewSurface(Widget child) => ProviderScope(
  child: Material(
    color: AleraTokens.bg,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space24),
      child: Center(child: child),
    ),
  ),
);

/// Design-system preview annotation. Use it instead of the bare `@Preview`
/// so every preview renders with Alera's dark theme and ambient scaffolding
/// already applied:
///
/// ```dart
/// @AleraPreview(name: 'Default', group: 'Icon button')
/// Widget aleraIconButtonPreview() => AleraIconButton(
///   tooltip: 'Close',
///   icon: AleraIcons.close,
///   onPressed: () {},
/// );
/// ```
///
/// Run the previewer with `flutter widget-preview start` from the repo root.
final class AleraPreview extends Preview {
  const AleraPreview({super.name, super.group, super.size})
    : super(
        brightness: Brightness.dark,
        theme: aleraPreviewTheme,
        wrapper: aleraPreviewSurface,
      );
}

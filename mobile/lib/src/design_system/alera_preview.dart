import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
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
      Theme(data: buildAleraMobileDarkTheme(), child: child);
}

/// Wraps a previewed component in the same ambient scaffolding the real app
/// provides: a [ProviderScope] for Riverpod reads and the global background so
/// dark surfaces render against the right backdrop.
Widget aleraPreviewSurface(Widget child) => ProviderScope(
  child: Material(
    color: AleraTokens.background,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.spaceXl),
      child: Center(child: child),
    ),
  ),
);

/// Design-system preview annotation for the mobile app. Use it instead of the
/// bare `@Preview` so every preview renders with Alera's dark theme and
/// ambient scaffolding already applied. Run the previewer with
/// `flutter widget-preview start` from the `mobile/` directory.
final class AleraPreview extends Preview {
  const AleraPreview({
    super.name,
    super.group,
    super.size = AleraTokens.previewPhoneSize,
  }) : super(
         brightness: Brightness.dark,
         theme: aleraPreviewTheme,
         wrapper: aleraPreviewSurface,
       );
}

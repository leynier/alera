import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Shared tokenized decoration for the pull-request panel's text fields
/// (composer create/link forms and the inline review editor).
InputDecoration pullRequestFieldDecoration(
  ThemeData theme, {
  required String hint,
}) {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: AleraTokens.surface,
    hintText: hint,
    hintStyle: theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundFaint,
    ),
    contentPadding: const EdgeInsets.all(AleraTokens.space12),
  );
}

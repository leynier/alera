import 'package:flutter/widgets.dart';

bool canApplyTextActionReplacement({
  required TextEditingValue captured,
  required TextEditingValue current,
  required String replacement,
}) {
  final selection = captured.selection;
  return current == captured &&
      replacement.trim().isNotEmpty &&
      selection.isValid &&
      !selection.isCollapsed &&
      selection.start >= 0 &&
      selection.end <= captured.text.length;
}

ReplaceTextIntent buildTextActionReplacementIntent({
  required TextEditingValue captured,
  required String replacement,
}) {
  return ReplaceTextIntent(captured, replacement, captured.selection, .toolbar);
}

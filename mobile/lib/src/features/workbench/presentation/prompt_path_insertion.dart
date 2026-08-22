import 'package:flutter/material.dart';

final RegExp _promptPathControlCharacters = RegExp(r'[\u0000-\u001F\u007F]');

void insertPromptPaths(TextEditingController controller, List<String> paths) {
  final sanitizedPaths = <String>[
    for (final path in paths) path.replaceAll(_promptPathControlCharacters, ''),
  ].where((path) => path.isNotEmpty).toList(growable: false);
  if (sanitizedPaths.isEmpty) {
    return;
  }

  final value = controller.value;
  final text = value.text;
  final selection = value.selection;
  final validSelection =
      selection.isValid && selection.start >= 0 && selection.end <= text.length;
  final start = validSelection ? selection.start : text.length;
  final end = validSelection ? selection.end : text.length;
  final insertion = sanitizedPaths.join('\n');
  final beforeSeparator = start > 0 && text.codeUnitAt(start - 1) != 0x0a;
  final afterSeparator = end < text.length && text.codeUnitAt(end) != 0x0a;
  final replacement = [
    text.substring(0, start),
    if (beforeSeparator) '\n',
    insertion,
    if (afterSeparator) '\n',
    text.substring(end),
  ].join();
  final cursorOffset =
      start +
      (beforeSeparator ? 1 : 0) +
      insertion.length +
      (afterSeparator ? 1 : 0);
  controller.value = value.copyWith(
    text: replacement,
    selection: TextSelection.collapsed(offset: cursorOffset),
    composing: TextRange.empty,
  );
}

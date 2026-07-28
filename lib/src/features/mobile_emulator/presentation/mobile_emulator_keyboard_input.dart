import 'package:flutter/services.dart';

String? mobileEmulatorPrintableText({
  required String? character,
  required bool controlPressed,
  required bool metaPressed,
  required bool altPressed,
}) {
  if (character == null ||
      character.isEmpty ||
      controlPressed ||
      metaPressed ||
      altPressed) {
    return null;
  }
  for (final codePoint in character.runes) {
    if (codePoint < 0x20 || (codePoint >= 0x7f && codePoint <= 0x9f)) {
      return null;
    }
  }
  return character;
}

String? mobileEmulatorInteractiveKey({
  required LogicalKeyboardKey logicalKey,
  required bool controlPressed,
  required bool metaPressed,
  required bool altPressed,
  required bool shiftPressed,
}) {
  if (controlPressed || metaPressed || altPressed || shiftPressed) {
    return null;
  }
  return switch (logicalKey) {
    LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter => 'enter',
    LogicalKeyboardKey.backspace => 'backspace',
    LogicalKeyboardKey.tab => 'tab',
    LogicalKeyboardKey.delete => 'deleteForward',
    LogicalKeyboardKey.arrowUp => 'arrowUp',
    LogicalKeyboardKey.arrowDown => 'arrowDown',
    LogicalKeyboardKey.arrowLeft => 'arrowLeft',
    LogicalKeyboardKey.arrowRight => 'arrowRight',
    LogicalKeyboardKey.escape => 'escape',
    _ => null,
  };
}

import 'dart:convert';

import 'package:alera/src/features/workbench/domain/terminal_agent_prompt_injection.dart';

/// Bytes for a composed prompt, without its submit CR.
///
/// Mirrors what `Terminal.paste` emits so deferring the Enter is the only
/// change in delivery: the emulator's live DECSET 2004 state decides the wrap,
/// not a guess about the payload.
List<int> buildTerminalSubmitPayloadBytes(
  String text, {
  required bool bracketedPasteMode,
}) {
  if (!bracketedPasteMode) {
    return utf8.encode(text);
  }
  return utf8.encode(
    '$terminalBracketedPasteStart$text$terminalBracketedPasteEnd',
  );
}

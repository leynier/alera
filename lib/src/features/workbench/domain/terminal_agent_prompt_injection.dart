import 'dart:convert';

/// Bracketed-paste start sequence (DECSET 2004 content).
const String terminalBracketedPasteStart = '\x1b[200~';

/// Bracketed-paste end sequence.
const String terminalBracketedPasteEnd = '\x1b[201~';

/// Delay before submitting after a multiline paste so agents render the paste.
const Duration terminalAgentPromptSubmitDelay = Duration(milliseconds: 500);

/// Preserve printable text, LF, and tab while rendering terminal controls as
/// inert ASCII markers.
String sanitizeAgentPromptText(String text) {
  final sanitized = StringBuffer();
  for (final codePoint in text.runes) {
    if (codePoint == 0x0a || codePoint == 0x09) {
      sanitized.writeCharCode(codePoint);
    } else if (codePoint <= 0x1f || codePoint == 0x7f) {
      sanitized.write(
        '<0x${codePoint.toRadixString(16).toUpperCase().padLeft(2, '0')}>',
      );
    } else {
      sanitized.writeCharCode(codePoint);
    }
  }
  return sanitized.toString();
}

/// Build UTF-8 bytes for a bracketed-paste agent/startup prompt (no submit).
List<int> buildAgentPromptPasteBytes(String prompt) {
  final sanitized = sanitizeAgentPromptText(prompt);
  return utf8.encode(
    '$terminalBracketedPasteStart$sanitized$terminalBracketedPasteEnd',
  );
}

/// Interactive shells known to enable bracketed paste for their line editor.
bool terminalShellSupportsBracketedPaste(String shell) {
  final executable = shell.replaceAll('\\', '/').split('/').last.toLowerCase();
  return executable == 'bash' || executable == 'zsh' || executable == 'fish';
}

/// Build shell-neutral startup input without terminal control markers.
List<int> buildPlainStartupCommandBytes(String command) {
  final singleLine = sanitizeAgentPromptText(
    command,
  ).replaceAll('\n', '<LF>').replaceAll('\t', '<TAB>');
  return utf8.encode('$singleLine\r');
}

/// Multiline or control-heavy startup commands need paste delivery so the
/// line editor does not treat embedded LFs as accept-line.
bool shouldUseBracketedPasteForStartupCommand(String command) {
  return command.runes.any(
        (codePoint) => codePoint < 0x20 || codePoint == 0x7f,
      ) ||
      command.length > 512;
}

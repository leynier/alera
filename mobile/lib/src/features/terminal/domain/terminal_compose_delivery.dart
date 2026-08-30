import 'dart:convert';

/// How one composed prompt reaches the PTY.
///
/// Text and its Enter used to travel as a single write, so the PTY saw them in
/// one burst. Agent TUIs run paste heuristics over input bursts and read a CR
/// that arrives inside the burst as a literal newline rather than a submit, so
/// the prompt landed in the composer instead of being sent. The host already
/// solves this: `deferredEnter` queues the CR as its own write half a second
/// later, atomically, so no other client can interleave between the two.
class const TerminalComposeDelivery({
  required final List<int> bytes,
  required final bool bracketedPaste,
  required final bool deferredEnter,
}) {
  /// Splits the prompt from its Enter when the host supports it. Without that
  /// support the only option is the single write, which is the behavior that
  /// produced the newline.
  factory forText(
    String text, {
    required bool withEnter,
    required bool hostSupportsDeferredInput,
  }) {
    if (!hostSupportsDeferredInput) {
      return TerminalComposeDelivery(
        bytes: utf8.encode(withEnter ? '$text\r' : text),
        bracketedPaste: false,
        deferredEnter: false,
      );
    }
    return TerminalComposeDelivery(
      bytes: utf8.encode(text),
      bracketedPaste: composedTextNeedsBracketedPaste(text),
      deferredEnter: withEnter,
    );
  }
}

/// Whether the host should wrap this text in bracketed paste before writing it.
///
/// Deliberately not every prompt: a short single-line command sent as a paste
/// gets collapsed into a placeholder by agent TUIs, and any program that has
/// not enabled DECSET 2004 leaks the markers as literal text. It is reserved
/// for the text that needs it, which is also the text the compose bar would
/// otherwise deliver as raw LFs into a line editor that treats them as
/// accept-line. Mirrors the desktop rule in
/// `lib/src/features/workbench/domain/terminal_agent_prompt_injection.dart`.
bool composedTextNeedsBracketedPaste(String text) {
  return text.runes.any((codePoint) => codePoint < 0x20 || codePoint == 0x7f) ||
      text.length > 512;
}

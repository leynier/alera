import 'dart:convert';

/// Bounded OSC 52 decoding for the mobile emulator.
///
/// A copy of the desktop policy (`terminal_osc52_clipboard.dart` at the
/// repository root), kept in sync by hand because `alera_mobile` does not
/// depend on the root package. Queries are never answered here: the phone's
/// clipboard is not the agent's to read.
const int terminalOsc52MaxPayloadCharacters = 128 * 1024;

sealed class const TerminalOsc52Request();

final class const TerminalOsc52Write(final String text)
    extends TerminalOsc52Request;

final class const TerminalOsc52Query() extends TerminalOsc52Request;

final class const TerminalOsc52Invalid() extends TerminalOsc52Request;

TerminalOsc52Request parseTerminalOsc52Request(List<String> args) {
  // OSC 52 permits an empty target as an alias for `s0`, but requiring an
  // explicit target keeps malformed escape sequences from mutating clipboard
  // state accidentally.
  if (args.length != 2 || !RegExp(r'^[cpqs0-7]+$').hasMatch(args.first)) {
    return const TerminalOsc52Invalid();
  }
  final payload = args[1];
  if (payload == '?') {
    return const TerminalOsc52Query();
  }
  if (payload.length > terminalOsc52MaxPayloadCharacters) {
    return const TerminalOsc52Invalid();
  }
  final normalized = payload.replaceAll(RegExp(r'\s'), '');
  if (normalized.length % 4 != 0 ||
      !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(normalized)) {
    return const TerminalOsc52Invalid();
  }
  return TerminalOsc52Write(
    utf8.decode(base64.decode(normalized), allowMalformed: true),
  );
}

String? decodeTerminalOsc52Payload(String selector, String payload) {
  final request = parseTerminalOsc52Request([selector, payload]);
  return request is TerminalOsc52Write ? request.text : null;
}

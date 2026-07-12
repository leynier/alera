import 'dart:convert';

const int terminalOsc52MaxPayloadCharacters = 128 * 1024;

sealed class TerminalOsc52Request {
  const TerminalOsc52Request();
}

final class TerminalOsc52Write extends TerminalOsc52Request {
  const TerminalOsc52Write(this.text);

  final String text;
}

final class TerminalOsc52Query extends TerminalOsc52Request {
  const TerminalOsc52Query();
}

final class TerminalOsc52Invalid extends TerminalOsc52Request {
  const TerminalOsc52Invalid();
}

TerminalOsc52Request parseTerminalOsc52Request(List<String> args) {
  // OSC 52 permits an empty target as an alias for `s0`, but requiring an
  // explicit target keeps malformed escape sequences from mutating clipboard
  // state accidentally. This matches the reference terminal policy in Orca.
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
  try {
    return TerminalOsc52Write(
      utf8.decode(base64.decode(normalized), allowMalformed: true),
    );
  } on FormatException {
    return const TerminalOsc52Invalid();
  }
}

import 'package:alera/src/features/session/domain/commands/alera_command.dart';

class ExpandedCustomCommand {
  const ExpandedCustomCommand({
    required this.text,
    required this.positionalArgs,
    required this.namedArgs,
  });

  final String text;
  final List<String> positionalArgs;
  final Map<String, String> namedArgs;
}

ExpandedCustomCommand expandCustomCommand(
  AleraCommand command,
  String rawArgs,
) {
  final content = command.content ?? '';
  final tokens = _tokenizeArgs(rawArgs);
  final positional = <String>[];
  final named = <String, String>{};
  for (final token in tokens) {
    final separator = token.indexOf('=');
    if (separator > 0) {
      final key = token.substring(0, separator).trim();
      final value = token.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        named[key.toUpperCase()] = value;
        continue;
      }
    }
    positional.add(token);
  }
  final expanded = content.replaceAllMapped(
    RegExp(r'\$\$|\$ARGUMENTS|\$[1-9]|\$[A-Za-z_][A-Za-z0-9_-]*'),
    (match) {
      final token = match.group(0) ?? '';
      if (token == r'$$') {
        return r'$';
      }
      final normalized = token.substring(1).toUpperCase();
      if (normalized == 'ARGUMENTS') {
        return rawArgs.trim();
      }
      final positionalIndex = int.tryParse(normalized);
      if (positionalIndex != null) {
        final resolvedIndex = positionalIndex - 1;
        if (resolvedIndex < 0 || resolvedIndex >= positional.length) {
          return '';
        }
        return positional[resolvedIndex];
      }
      return named[normalized] ?? '';
    },
  );
  return ExpandedCustomCommand(
    text: expanded.trim(),
    positionalArgs: positional,
    namedArgs: named,
  );
}

List<String> _tokenizeArgs(String rawArgs) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var escaping = false;
  for (var i = 0; i < rawArgs.length; i++) {
    final char = rawArgs[i];
    if (escaping) {
      buffer.write(char);
      escaping = false;
      continue;
    }
    if (char == r'\') {
      escaping = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"' || char == '\'') {
      quote = char;
      continue;
    }
    if (RegExp(r'\s').hasMatch(char)) {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }
  if (escaping) {
    buffer.write(r'\');
  }
  if (buffer.isNotEmpty) {
    tokens.add(buffer.toString());
  }
  return tokens;
}

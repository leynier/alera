String expandCodexSavedPrompt(String body, String rawArguments) {
  final arguments = _tokenizeArguments(rawArguments);
  final positional = <String>[];
  final named = <String, String>{};
  for (final argument in arguments) {
    final separator = argument.indexOf('=');
    if (separator > 0 && separator < argument.length - 1) {
      named[argument.substring(0, separator).toUpperCase()] = argument
          .substring(separator + 1);
    } else {
      positional.add(argument);
    }
  }
  return body.replaceAllMapped(
    RegExp(r'\$\$|\$ARGUMENTS|\$[1-9]|\$[A-Za-z_][A-Za-z0-9_-]*'),
    (token) {
      final value = token.group(0)!;
      if (value == r'$$') return r'$';
      final key = value.substring(1).toUpperCase();
      if (key == 'ARGUMENTS') return rawArguments;
      final position = int.tryParse(key);
      if (position != null) {
        return position <= positional.length ? positional[position - 1] : '';
      }
      return named[key] ?? '';
    },
  ).trim();
}

List<String> _tokenizeArguments(String input) {
  final arguments = <String>[];
  final current = StringBuffer();
  String? quote;
  var escaping = false;
  for (final rune in input.runes) {
    final character = String.fromCharCode(rune);
    if (escaping) {
      current.write(character);
      escaping = false;
    } else if (character == r'\') {
      escaping = true;
    } else if (quote != null) {
      if (character == quote) {
        quote = null;
      } else {
        current.write(character);
      }
    } else if (character == '"' || character == "'") {
      quote = character;
    } else if (RegExp(r'\s').hasMatch(character)) {
      if (current.isNotEmpty) {
        arguments.add(current.toString());
        current.clear();
      }
    } else {
      current.write(character);
    }
  }
  if (escaping) current.write(r'\');
  if (current.isNotEmpty) arguments.add(current.toString());
  return arguments;
}

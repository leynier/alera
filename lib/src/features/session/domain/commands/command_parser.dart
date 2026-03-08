class ParsedSlashCommand {
  const ParsedSlashCommand({
    required this.rawInput,
    required this.firstLine,
    required this.name,
    required this.rawArgs,
    required this.hasArgs,
    required this.remainingText,
  });

  final String rawInput;
  final String firstLine;
  final String name;
  final String rawArgs;
  final bool hasArgs;
  final String remainingText;

  String get normalizedName => name.trim().toLowerCase();
}

ParsedSlashCommand? parseSlashCommand(String text) {
  if (text.isEmpty) {
    return null;
  }
  final normalized = text.replaceAll('\r\n', '\n');
  final newlineIndex = normalized.indexOf('\n');
  final firstLine = newlineIndex == -1
      ? normalized
      : normalized.substring(0, newlineIndex);
  final remainingText = newlineIndex == -1
      ? ''
      : normalized.substring(newlineIndex + 1);
  if (firstLine.isEmpty || !firstLine.startsWith('/')) {
    return null;
  }
  final withoutSlash = firstLine.substring(1);
  if (withoutSlash.isEmpty || withoutSlash.startsWith(' ')) {
    return null;
  }
  final firstSpace = withoutSlash.indexOf(RegExp(r'\s'));
  if (firstSpace == -1) {
    final name = withoutSlash.trim();
    if (!_isValidCommandName(name)) {
      return null;
    }
    return ParsedSlashCommand(
      rawInput: text,
      firstLine: firstLine,
      name: name,
      rawArgs: '',
      hasArgs: false,
      remainingText: remainingText,
    );
  }
  final name = withoutSlash.substring(0, firstSpace).trim();
  if (!_isValidCommandName(name)) {
    return null;
  }
  final rawArgs = withoutSlash.substring(firstSpace).trim();
  return ParsedSlashCommand(
    rawInput: text,
    firstLine: firstLine,
    name: name,
    rawArgs: rawArgs,
    hasArgs: rawArgs.isNotEmpty,
    remainingText: remainingText,
  );
}

bool looksLikeSlashQuery(String text, int cursorOffset) {
  if (cursorOffset < 0 || cursorOffset > text.length) {
    return false;
  }
  final beforeCursor = text.substring(0, cursorOffset);
  final firstLine = beforeCursor.split('\n').firstOrNull ?? '';
  if (!firstLine.startsWith('/')) {
    return false;
  }
  if (firstLine.length == 1) {
    return true;
  }
  final withoutSlash = firstLine.substring(1);
  if (withoutSlash.startsWith(' ')) {
    return false;
  }
  return !withoutSlash.contains(RegExp(r'\s'));
}

String extractSlashQuery(String text, int cursorOffset) {
  if (cursorOffset < 0 || cursorOffset > text.length) {
    return '';
  }
  final beforeCursor = text.substring(0, cursorOffset);
  final firstLine = beforeCursor.split('\n').firstOrNull ?? '';
  if (!firstLine.startsWith('/') || firstLine.length < 2) {
    return '';
  }
  final withoutSlash = firstLine.substring(1);
  if (withoutSlash.startsWith(' ')) {
    return '';
  }
  final firstWhitespace = withoutSlash.indexOf(RegExp(r'\s'));
  if (firstWhitespace != -1) {
    return '';
  }
  return withoutSlash.trim();
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

bool _isValidCommandName(String value) {
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value);
}

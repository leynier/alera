part of 'codex_runtime_home_service.dart';

List<_TomlSection> _tomlSections(String config) {
  final lines = config.split('\n');
  final sections = <_TomlSection>[];
  var start = -1;
  var header = '';
  var multilineState = const _TomlMultilineState();
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final nextHeader = _isInsideTomlMultilineString(multilineState)
        ? null
        : _tomlTableHeader(line);
    if (nextHeader == null) {
      multilineState = _updateTomlMultilineState(multilineState, line);
      continue;
    }
    if (start >= 0) {
      sections.add(
        _TomlSection(
          header: header,
          block: lines.sublist(start, index).join('\n'),
          start: start,
        ),
      );
    }
    start = index;
    header = nextHeader;
    multilineState = _updateTomlMultilineState(multilineState, line);
  }
  if (start >= 0) {
    sections.add(
      _TomlSection(
        header: header,
        block: lines.sublist(start).join('\n'),
        start: start,
      ),
    );
  }
  return sections;
}

bool _isHookStateSection(String header) =>
    header.trimLeft().startsWith('[hooks.state.');

bool _isProjectSection(String header) =>
    header.trimLeft().startsWith('[projects.');

String _sectionHeaderKey(String header) => header.trim();

String _joinTomlBlocks(List<String> blocks) {
  final normalized = <String>[
    for (final block in blocks)
      if (block.trim().isNotEmpty) block.trimRight(),
  ];
  if (normalized.isEmpty) {
    return '';
  }
  return '${normalized.join('\n\n')}\n';
}

int _findNextTableHeader(String text) {
  var cursor = 0;
  var multilineState = const _TomlMultilineState();
  while (cursor < text.length) {
    final newlineIndex = text.indexOf('\n', cursor);
    final lineEnd = newlineIndex < 0 ? text.length : newlineIndex;
    final line = text
        .substring(cursor, lineEnd)
        .replaceFirst(RegExp(r'\r$'), '');
    if (!_isInsideTomlMultilineString(multilineState) &&
        _tomlTableHeader(line) != null) {
      return cursor;
    }
    multilineState = _updateTomlMultilineState(multilineState, line);
    if (newlineIndex < 0) {
      return -1;
    }
    cursor = newlineIndex + 1;
  }
  return -1;
}

String? _tomlTableHeader(String line) {
  final normalized = line.replaceFirst(RegExp(r'\r$'), '');
  final trimmedLeft = normalized.trimLeft();
  final leadingLength = normalized.length - trimmedLeft.length;
  final headerEnd = _tomlTableHeaderEnd(trimmedLeft);
  if (headerEnd == null) {
    return null;
  }
  return normalized.substring(0, leadingLength + headerEnd).trimRight();
}

int? _tomlTableHeaderEnd(String line) {
  if (!line.startsWith('[')) {
    return null;
  }
  final isArrayHeader = line.startsWith('[[');
  var index = isArrayHeader ? 2 : 1;
  var inBasicQuote = false;
  var inLiteralQuote = false;
  while (index < line.length) {
    final char = line[index];
    if (inBasicQuote) {
      if (char == r'\' && index + 1 < line.length) {
        index += 2;
        continue;
      }
      if (char == '"') {
        inBasicQuote = false;
      }
      index += 1;
      continue;
    }
    if (inLiteralQuote) {
      if (char == "'") {
        inLiteralQuote = false;
      }
      index += 1;
      continue;
    }
    if (char == '"') {
      inBasicQuote = true;
      index += 1;
      continue;
    }
    if (char == "'") {
      inLiteralQuote = true;
      index += 1;
      continue;
    }
    if (char == ']') {
      if (isArrayHeader) {
        if (line.length <= index + 1 || line[index + 1] != ']') {
          return null;
        }
        final tail = line.substring(index + 2);
        return RegExp(r'^\s*(#.*)?$').hasMatch(tail) ? index + 2 : null;
      }
      final tail = line.substring(index + 1);
      return RegExp(r'^\s*(#.*)?$').hasMatch(tail) ? index + 1 : null;
    }
    index += 1;
  }
  return null;
}

bool _isInsideTomlMultilineString(_TomlMultilineState state) {
  return state.basic || state.literal;
}

_TomlMultilineState _updateTomlMultilineState(
  _TomlMultilineState state,
  String line,
) {
  var mode = state.basic
      ? _TomlMultilineMode.basic
      : state.literal
      ? _TomlMultilineMode.literal
      : _TomlMultilineMode.none;
  var index = 0;
  while (index < line.length) {
    if (mode == _TomlMultilineMode.basic) {
      if (line[index] == r'\' && index + 1 < line.length) {
        index += 2;
        continue;
      }
      if (line.startsWith('"""', index)) {
        mode = _TomlMultilineMode.none;
        index += 3;
        continue;
      }
      index += 1;
      continue;
    }
    if (mode == _TomlMultilineMode.literal) {
      if (line.startsWith("'''", index)) {
        mode = _TomlMultilineMode.none;
        index += 3;
        continue;
      }
      index += 1;
      continue;
    }

    final char = line[index];
    if (char == '#') {
      break;
    }
    if (line.startsWith('"""', index)) {
      mode = _TomlMultilineMode.basic;
      index += 3;
      continue;
    }
    if (line.startsWith("'''", index)) {
      mode = _TomlMultilineMode.literal;
      index += 3;
      continue;
    }
    if (char == '"') {
      index = _skipTomlBasicString(line, index + 1);
      continue;
    }
    if (char == "'") {
      index = _skipTomlLiteralString(line, index + 1);
      continue;
    }
    index += 1;
  }
  return _TomlMultilineState(
    basic: mode == _TomlMultilineMode.basic,
    literal: mode == _TomlMultilineMode.literal,
  );
}

int _skipTomlBasicString(String line, int startIndex) {
  var index = startIndex;
  while (index < line.length) {
    final char = line[index];
    if (char == r'\' && index + 1 < line.length) {
      index += 2;
      continue;
    }
    if (char == '"') {
      return index + 1;
    }
    index += 1;
  }
  return index;
}

int _skipTomlLiteralString(String line, int startIndex) {
  final endIndex = line.indexOf("'", startIndex);
  return endIndex < 0 ? line.length : endIndex + 1;
}

String _shQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

String _resolveHome(Map<String, String>? environment) {
  final env = environment ?? Platform.environment;
  if (Platform.isWindows) {
    final profile = env['USERPROFILE']?.trim();
    if (profile != null && profile.isNotEmpty) {
      return profile;
    }
  }
  final home = env['HOME']?.trim();
  if (home != null && home.isNotEmpty) {
    return home;
  }
  final profile = env['USERPROFILE']?.trim();
  if (profile != null && profile.isNotEmpty) {
    return profile;
  }
  return Directory.current.path;
}

void _createResourceLink({
  required String sourcePath,
  required String targetPath,
}) {
  Link(targetPath).createSync(sourcePath, recursive: true);
}

String _fileSystemEntityTypeName(FileSystemEntityType type) {
  if (type == FileSystemEntityType.directory) {
    return 'directory';
  }
  if (type == FileSystemEntityType.file) {
    return 'file';
  }
  if (type == FileSystemEntityType.link) {
    return 'link';
  }
  if (type == FileSystemEntityType.notFound) {
    return 'notFound';
  }
  return type.toString();
}

final class _TomlSection {
  const _TomlSection({
    required this.header,
    required this.block,
    required this.start,
  });

  final String header;
  final String block;
  final int start;
}

enum _TomlMultilineMode { none, basic, literal }

final class _TomlMultilineState {
  const _TomlMultilineState({this.basic = false, this.literal = false});

  final bool basic;
  final bool literal;
}

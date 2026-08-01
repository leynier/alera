import 'package:path/path.dart' as p;

class ProjectConfigPathException implements Exception {
  ProjectConfigPathException(this.message);

  final String message;

  @override
  String toString() => message;
}

String normalizeProjectConfigPath(String value, String label) {
  final trimmedInput = value.trim();
  final normalizedInput = trimmedInput.replaceAll('\\', '/');
  if (normalizedInput.isEmpty ||
      p.posix.isAbsolute(normalizedInput) ||
      p.windows.isAbsolute(trimmedInput) ||
      p.windows.isAbsolute(normalizedInput)) {
    throw ProjectConfigPathException('$label must be a relative path');
  }
  final normalized = p.posix.normalize(normalizedInput);
  if (normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      p.posix.split(normalized).contains('..')) {
    throw ProjectConfigPathException('$label must stay inside the project');
  }
  return normalized;
}

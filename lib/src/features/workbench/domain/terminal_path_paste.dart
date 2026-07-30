import 'package:alera/src/features/workbench/domain/terminal_image_paste.dart';

final RegExp _terminalPathWhitespace = RegExp(r'\s');

/// Formats one absolute path for pasting into a terminal PTY.
///
/// Bare path when there is no whitespace; otherwise POSIX single-quoted, with a
/// trailing space so multiple drops stay separated (Jean / native-terminal style).
String formatPathForTerminalPaste(String path) {
  final sanitized = sanitizeTerminalImagePastePath(path.trim());
  if (sanitized.isEmpty) {
    return '';
  }
  if (!_terminalPathWhitespace.hasMatch(sanitized)) {
    return '$sanitized ';
  }
  return "'${sanitized.replaceAll("'", "'\\''")}' ";
}

/// Formats several absolute paths for a single terminal paste.
String formatPathsForTerminalPaste(Iterable<String> paths) {
  final buffer = StringBuffer();
  for (final path in paths) {
    buffer.write(formatPathForTerminalPaste(path));
  }
  return buffer.toString();
}

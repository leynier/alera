import 'dart:async';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';

/// Shown only when an error carries no readable text at all.
const String unknownErrorMessage =
    'An unexpected error occurred. See the logs for details.';

/// Dart and wrapper type names that `toString()` puts in front of the real
/// message: `Bad state: `, `Exception: `, `RelayCryptoException: `, and so on.
final RegExp _typePrefix = RegExp(
  r'^(?:Bad state|Invalid argument\(s\)|Unsupported operation|'
  r'Unimplemented|Exception|Error|[A-Z][A-Za-z0-9]*(?:Exception|Error))'
  r'(?:\([^)]*\))?:(?:\s+|$)',
);

final RegExp _instanceOf = RegExp(r"^Instance of '[^']*'$");

/// The text the phone shows for [error]: the underlying cause, without Dart
/// type prefixes or wrapper class names, and never an empty string.
///
/// This mirrors the desktop formatter of the same name. It is for display
/// only: code that classifies an error MUST keep matching on the typed error,
/// its `code`, or its raw message, never on this text.
String userFacingErrorMessage(Object? error, {String? fallback}) {
  final text = _messageOf(error);
  final cleaned = text == null ? '' : _clean(text);
  if (cleaned.isNotEmpty) {
    return cleaned;
  }
  final fallbackText = fallback?.trim();
  return fallbackText == null || fallbackText.isEmpty
      ? unknownErrorMessage
      : fallbackText;
}

/// One consistent sentence for a failed user action:
/// `Could not archive workspace: <cause>`.
///
/// [action] is the lowercase verb phrase, such as `archive workspace`.
String actionFailureMessage(String action, Object? error) {
  final cause = userFacingErrorMessage(error, fallback: '');
  final subject = 'Could not ${action.trim()}';
  if (cause.isEmpty || cause == unknownErrorMessage) {
    return '$subject. $unknownErrorMessage';
  }
  return '$subject: $cause';
}

/// Removes the leading Dart type names an error's `toString()` adds, however
/// many layers deep they are nested.
String stripErrorTypePrefixes(String raw) {
  var message = raw.trim();
  while (true) {
    final match = _typePrefix.firstMatch(message);
    if (match == null) {
      return message;
    }
    message = message.substring(match.end).trim();
  }
}

String? _messageOf(Object? error) {
  if (error == null) {
    return null;
  }
  return switch (error) {
    final RuntimeRequestError error => error.message,
    final TimeoutException error =>
      error.message?.trim().isNotEmpty == true
          ? error.message
          : 'The operation did not finish in time.',
    final FileSystemException error => _fileSystemMessage(error),
    final StateError error => error.message,
    final FormatException error => error.message,
    final UnsupportedError error => error.message ?? error.toString(),
    final ArgumentError error => error.message?.toString() ?? error.toString(),
    _ => error.toString(),
  };
}

String _clean(String text) {
  final stripped = stripErrorTypePrefixes(text);
  if (stripped.isEmpty || _instanceOf.hasMatch(stripped)) {
    return '';
  }
  return _capitalizeLeadingWord(stripped);
}

/// Runtime and git messages often start lowercase (`cannot push detached
/// HEAD`). Only a plain lowercase word is capitalized, so paths, commands and
/// identifiers such as `npm` or `./setup.sh` keep their spelling.
String _capitalizeLeadingWord(String text) {
  final firstWord = RegExp(r'^[a-z]+(?=[\s,:]|$)').firstMatch(text);
  if (firstWord == null) {
    return text;
  }
  const keepLowercase = <String>{'git', 'npm', 'pnpm', 'yarn', 'gh', 'glab'};
  if (keepLowercase.contains(firstWord.group(0))) {
    return text;
  }
  return text[0].toUpperCase() + text.substring(1);
}

String _fileSystemMessage(FileSystemException error) {
  final buffer = StringBuffer(
    error.message.trim().isEmpty ? 'File system error' : error.message.trim(),
  );
  final path = error.path?.trim();
  if (path != null && path.isNotEmpty) {
    buffer.write(' ($path)');
  }
  final osMessage = error.osError?.message.trim();
  if (osMessage != null && osMessage.isNotEmpty) {
    buffer.write(': $osMessage');
  }
  return buffer.toString();
}

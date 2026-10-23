import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/ai_assist/application/ai_assist_errors.dart';
import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/rust/api/ai_dictation.dart' as native_dictation;
import 'package:alera/src/rust/api/git.dart' as native_git;
import 'package:alera/src/rust/api/merman_viewer.dart' as native_merman;
import 'package:alera/src/rust/api/reading_diff.dart' as native_reading_diff;
import 'package:alera/src/rust/api/workspace_files.dart' as native_files;
import 'package:alera/src/rust/api/workspace_search.dart' as native_search;
import 'package:alera/src/shared/infra/git/git_error_message.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';

/// Shown only when an error carries no readable text at all.
const String unknownErrorMessage =
    'An unexpected error occurred. See the logs for details.';

/// Dart and wrapper type names that `toString()` puts in front of the real
/// message: `Bad state: `, `Exception: `, `GitCliException: `, and so on.
final RegExp _typePrefix = RegExp(
  r'^(?:Bad state|Invalid argument\(s\)|Unsupported operation|'
  r'Unimplemented|Exception|Error|[A-Z][A-Za-z0-9]*(?:Exception|Error))'
  r'(?:\([^)]*\))?:(?:\s+|$)',
);

final RegExp _instanceOf = RegExp(r"^Instance of '[^']*'$");

/// The text the UI shows for [error]: the underlying cause, without Dart type
/// prefixes or wrapper class names, and never an empty string.
///
/// This is for display only. Code that classifies an error MUST keep matching
/// on the typed error or its raw message, never on this text.
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
  final remote = remoteWorkspaceErrorMessage(error);
  if (remote != null) {
    return remote;
  }
  return switch (error) {
    final GitException error => gitErrorMessage(
      _withCleanContext(error, stripErrorTypePrefixes(error.context)),
    ),
    final ForgeException error => error.message,
    final AiAssistException error => error.message,
    final TerminalHostConflictException error => error.message,
    final TerminalHostRequestTimeoutException error =>
      'The Alera runtime did not answer within '
          '${_seconds(error.duration)}. Try again, or restart the runtime '
          'from the status bar if this keeps happening.',
    final TerminalHostConnectionClosedException error => _joinCause(
      'Lost the connection to the Alera runtime',
      error.reason,
    ),
    TerminalHostStartupException() =>
      'The Alera runtime did not start in time. Restart Alera, then try again.',
    final TimeoutException error =>
      error.message?.trim().isNotEmpty == true
          ? error.message
          : error.duration == null
          ? 'The operation did not finish in time.'
          : 'The operation did not finish within ${_seconds(error.duration!)}.',
    final native_files.WorkspaceFileError error => _withDetail(
      _workspaceFileKindMessage(error.kind),
      error.context,
    ),
    final native_search.WorkspaceSearchError error => _withDetail(
      _workspaceSearchKindMessage(error.kind),
      error.context,
    ),
    final native_merman.MermanViewerError error => _withDetail(
      _mermanKindMessage(error.kind),
      error.context,
    ),
    final native_git.GitError error =>
      error.context.trim().isEmpty ? 'Git operation failed.' : error.context,
    final native_reading_diff.ReadingDiffError error => error.message,
    final native_dictation.AiDictationError error => error.message,
    final FileSystemException error => _fileSystemMessage(error),
    final ProcessException error => _withDetail(
      'Could not run ${error.executable}',
      error.message,
    ),
    final StateError error => error.message,
    final FormatException error => error.message,
    final UnsupportedError error => error.message,
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

GitException _withCleanContext(GitException error, String context) {
  if (context == error.context) {
    return error;
  }
  return switch (error) {
    NotARepositoryException() => NotARepositoryException(context),
    AccessDeniedException() => AccessDeniedException(context),
    BranchNotFoundException() => BranchNotFoundException(context),
    BranchAlreadyExistsException() => BranchAlreadyExistsException(context),
    InvalidBranchNameException() => InvalidBranchNameException(context),
    WorktreeAlreadyExistsException() => WorktreeAlreadyExistsException(context),
    WorktreeNotFoundException() => WorktreeNotFoundException(context),
    CloneFailedException() => CloneFailedException(context),
    GitCliException() => GitCliException(context),
    DetachedHeadException() => DetachedHeadException(context),
    NoUpstreamException() => NoUpstreamException(context),
    RemoteNotFoundException() => RemoteNotFoundException(context),
    NothingToCommitException() => NothingToCommitException(context),
    WorkspaceScopeException() => WorkspaceScopeException(context),
    MissingIdentityException() => MissingIdentityException(context),
    GitConflictException() => GitConflictException(context),
    GitInternalException() => GitInternalException(context),
  };
}

String _workspaceFileKindMessage(native_files.WorkspaceFileErrorKind kind) {
  return switch (kind) {
    native_files.WorkspaceFileErrorKind.invalidPath => 'The path is not valid',
    native_files.WorkspaceFileErrorKind.outsideWorkspace =>
      'The path is outside the workspace',
    native_files.WorkspaceFileErrorKind.notFound => 'The item was not found',
    native_files.WorkspaceFileErrorKind.alreadyExists =>
      'An item with that name already exists',
    native_files.WorkspaceFileErrorKind.protectedPath =>
      'The path is protected',
    native_files.WorkspaceFileErrorKind.unsupported =>
      'This operation is not supported for the item',
    native_files.WorkspaceFileErrorKind.conflict => 'The file changed on disk',
    native_files.WorkspaceFileErrorKind.io => 'The file operation failed',
  };
}

String _workspaceSearchKindMessage(
  native_search.WorkspaceSearchErrorKind kind,
) {
  return switch (kind) {
    native_search.WorkspaceSearchErrorKind.invalidPath =>
      'The search path is not valid',
    native_search.WorkspaceSearchErrorKind.outsideWorkspace =>
      'The search path is outside the workspace',
    native_search.WorkspaceSearchErrorKind.invalidPattern =>
      'The search pattern is not valid',
    native_search.WorkspaceSearchErrorKind.io => 'The search failed',
    native_search.WorkspaceSearchErrorKind.cancelled =>
      'The search was canceled',
  };
}

String _mermanKindMessage(native_merman.MermanViewerErrorKind kind) {
  return switch (kind) {
    native_merman.MermanViewerErrorKind.invalidPath => 'The path is not valid',
    native_merman.MermanViewerErrorKind.outsideWorkspace =>
      'The path is outside the workspace',
    native_merman.MermanViewerErrorKind.notFound => 'The file was not found',
    native_merman.MermanViewerErrorKind.unsupported =>
      'This diagram type is not supported',
    native_merman.MermanViewerErrorKind.render =>
      'The diagram could not be rendered',
    native_merman.MermanViewerErrorKind.io => 'The diagram could not be read',
  };
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

String _withDetail(String summary, String? detail) {
  final cleaned = detail == null ? '' : stripErrorTypePrefixes(detail);
  if (cleaned.isEmpty) {
    return '$summary.';
  }
  return '$summary: $cleaned';
}

String _joinCause(String summary, Object? cause) {
  if (cause == null) {
    return '$summary.';
  }
  final detail = _messageOf(cause);
  return _withDetail(summary, detail == null ? null : _clean(detail));
}

String _seconds(Duration duration) {
  final seconds = (duration.inMilliseconds / 1000).ceil();
  return seconds == 1 ? '1 second' : '$seconds seconds';
}

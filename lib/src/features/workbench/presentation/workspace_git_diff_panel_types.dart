part of 'workspace_git_diff_panel.dart';

final Logger _gitDiffPanelLogger = Logger('WorkspaceGitDiffPanel');

/// Git failures read the same here as on the phone (`gitErrorMessage`); any
/// other failure shows its own cause rather than a generic sentence.
String _messageFor(Object? error) => userFacingErrorMessage(error);

typedef OpenGitDiffTabCallback = Future<void> Function({
  String? relativePath,
  GitChangeArea? area,
  String? gitDiffRoot,
  required WorkspaceGitDiffScope scope,
  bool preview,
  bool oppositePanel,
});

typedef OpenGitCommitDiffTabCallback = Future<void> Function({
  String? relativePath,
  String? oldPath,
  required WorkspaceGitDiffScope scope,
  String? gitDiffRoot,
  required String commitOid,
  String? parentOid,
  required String compareRef,
  String? subject,
  String? message,
  bool preview,
  bool oppositePanel,
});

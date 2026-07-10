part of 'workspace_git_diff_panel.dart';

typedef OpenGitDiffTabCallback =
    Future<void> Function({
      String? relativePath,
      GitChangeArea? area,
      String? gitDiffRoot,
      required WorkspaceGitDiffScope scope,
    });

typedef OpenGitCommitDiffTabCallback =
    Future<void> Function({
      String? relativePath,
      String? oldPath,
      required WorkspaceGitDiffScope scope,
      String? gitDiffRoot,
      required String commitOid,
      String? parentOid,
      required String compareRef,
      String? subject,
      String? message,
    });

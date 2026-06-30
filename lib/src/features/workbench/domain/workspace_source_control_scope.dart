import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:path/path.dart' as p;

class WorkspaceSourceControlScope {
  const WorkspaceSourceControlScope({
    required this.workspaceId,
    required this.workspacePath,
    required this.path,
    this.relativeRoot,
  });

  final String workspaceId;
  final String workspacePath;
  final String path;
  final String? relativeRoot;

  bool get isWorkspaceRoot => relativeRoot == null;

  String get displayPath => relativeRoot ?? '';

  static WorkspaceSourceControlScope? resolve({
    required Project? project,
    required Workspace? workspace,
    required WorkbenchViewPrefs prefs,
  }) {
    if (project == null || workspace == null) {
      return null;
    }
    if (project.isGitRepository) {
      return WorkspaceSourceControlScope(
        workspaceId: workspace.id,
        workspacePath: workspace.path,
        path: workspace.path,
      );
    }
    final relativeRoot = normalizeSourceControlRootRelativePath(
      prefs.sourceControlRootByWorkspaceId[workspace.id],
    );
    if (relativeRoot == null) {
      return null;
    }
    return WorkspaceSourceControlScope(
      workspaceId: workspace.id,
      workspacePath: workspace.path,
      path: sourceControlRootAbsolutePath(
        workspacePath: workspace.path,
        relativeRoot: relativeRoot,
      ),
      relativeRoot: relativeRoot,
    );
  }

  String? toSourceRelativePath(String? workspaceRelativePath) {
    if (workspaceRelativePath == null || relativeRoot == null) {
      return workspaceRelativePath;
    }
    final normalized = normalizeWorkspaceRelativePath(workspaceRelativePath);
    if (normalized == null) {
      return null;
    }
    if (normalized == relativeRoot) {
      return '';
    }
    final prefix = '$relativeRoot/';
    if (!normalized.startsWith(prefix)) {
      return null;
    }
    return normalized.substring(prefix.length);
  }

  String? toWorkspaceRelativePath(String? sourceRelativePath) {
    if (sourceRelativePath == null || relativeRoot == null) {
      return sourceRelativePath;
    }
    final normalized = normalizeWorkspaceRelativePath(sourceRelativePath);
    if (normalized == null) {
      return relativeRoot;
    }
    return p.posix.join(relativeRoot!, normalized);
  }
}

String? normalizeSourceControlRootRelativePath(String? value) {
  final normalized = normalizeWorkspaceRelativePath(value);
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? normalizeWorkspaceRelativePath(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
  if (normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      p.posix.isAbsolute(normalized)) {
    return null;
  }
  return normalized;
}

String sourceControlRootAbsolutePath({
  required String workspacePath,
  required String relativeRoot,
}) {
  return p.joinAll(<String>[workspacePath, ...relativeRoot.split('/')]);
}

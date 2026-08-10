part of 'workspace_git_diff_surface_test.dart';

class _GitDiffSurfaceTestController extends WorkbenchController {
  final List<String> openedRelativePaths = <String>[];

  @override
  WorkbenchState build() => const WorkbenchState();

  @override
  Future<WorkspaceTabRecord> openEditorTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
  }) async {
    openedRelativePaths.add(relativePath);
    final now = DateTime.utc(2026, 6, 6);
    return WorkspaceTabRecord(
      id: 'editor-${openedRelativePaths.length}',
      workspaceId: workspace.id,
      kind: WorkspaceTabKind.editor,
      title: relativePath.split('/').last,
      createdAt: now,
      updatedAt: now,
      payload: <String, Object?>{workspaceTabFilePathPayloadKey: relativePath},
    );
  }
}

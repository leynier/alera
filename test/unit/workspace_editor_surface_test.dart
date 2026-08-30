import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/presentation/workspace_editor_surface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session registration does not consume pending reveal', () {
    final registry = EditorSessionRegistry();
    const target = WorkspaceEditorRevealTarget(
      line: 2,
      column: 3,
      matchLength: 4,
    );

    registry.reveal('tab-b', target);
    registry.register(
      'tab-b',
      EditorSessionHandle(
        isDirty: () => false,
        save: () async {},
        discard: () async {},
      ),
    );

    expect(registry.takePendingReveal('tab-b'), target);
    expect(registry.takePendingReveal('tab-b'), isNull);
  });

  test('reveal range maps raw tab columns to expanded editor columns', () {
    final range = workspaceEditorDisplayRevealRange(
      rawText: '\tfoo\n',
      lineNumber: 1,
      rawColumn: 2,
      rawMatchLength: 3,
      tabSize: 4,
    );

    expect(range.columnIndex, 4);
    expect(range.matchLength, 3);
  });

  test('reveal range uses UTF-16 offsets after non-BMP characters', () {
    final range = workspaceEditorDisplayRevealRange(
      rawText: '🙂needle\n',
      lineNumber: 1,
      rawColumn: 2,
      rawMatchLength: 6,
      tabSize: 4,
    );

    expect(range.columnIndex, 2);
    expect(range.matchLength, 6);
  });

  test('reveal range includes non-BMP characters inside the match', () {
    final range = workspaceEditorDisplayRevealRange(
      rawText: '🙂ne🙂edle\n',
      lineNumber: 1,
      rawColumn: 2,
      rawMatchLength: 7,
      tabSize: 4,
    );

    expect(range.columnIndex, 2);
    expect(range.matchLength, 8);
  });

  test('load request matcher rejects stale editor reads', () {
    expect(
      workspaceEditorLoadRequestMatches(
        requestId: 2,
        currentRequestId: 2,
        workspacePath: '/repo/alera',
        activeWorkspacePath: '/repo/alera',
        filePath: 'lib/main.dart',
        activeFilePath: 'lib/main.dart',
      ),
      isTrue,
    );
    expect(
      workspaceEditorLoadRequestMatches(
        requestId: 1,
        currentRequestId: 2,
        workspacePath: '/repo/alera',
        activeWorkspacePath: '/repo/alera',
        filePath: 'lib/main.dart',
        activeFilePath: 'lib/main.dart',
      ),
      isFalse,
    );
    expect(
      workspaceEditorLoadRequestMatches(
        requestId: 2,
        currentRequestId: 2,
        workspacePath: '/repo/alera',
        activeWorkspacePath: '/repo/other',
        filePath: 'lib/main.dart',
        activeFilePath: 'lib/main.dart',
      ),
      isFalse,
    );
    expect(
      workspaceEditorLoadRequestMatches(
        requestId: 2,
        currentRequestId: 2,
        workspacePath: '/repo/alera',
        activeWorkspacePath: '/repo/alera',
        filePath: 'lib/main.dart',
        activeFilePath: 'lib/other.dart',
      ),
      isFalse,
    );
  });

  test('editor diff target uses focused source control root', () {
    final workspace = _workspace();

    final target = workspaceEditorDiffTargetForFile(
      workspace: workspace,
      filePath: 'packages/app/lib/main.dart',
      sourceControlScope: WorkspaceSourceControlScope(
        workspaceId: workspace.id,
        workspacePath: workspace.path,
        path: '/repo/alera/packages/app',
        relativeRoot: 'packages/app',
      ),
    );

    expect(target, isNotNull);
    expect(target!.gitPath, '/repo/alera/packages/app');
    expect(target.gitFilePath, 'lib/main.dart');
    expect(target.gitDiffRoot, 'packages/app');
  });

  test('editor diff target rejects files outside focused source root', () {
    final workspace = _workspace();

    final target = workspaceEditorDiffTargetForFile(
      workspace: workspace,
      filePath: 'docs/readme.md',
      sourceControlScope: WorkspaceSourceControlScope(
        workspaceId: workspace.id,
        workspacePath: workspace.path,
        path: '/repo/alera/packages/app',
        relativeRoot: 'packages/app',
      ),
    );

    expect(target, isNull);
  });

  test(
    'editor diff target uses workspace root without focused source root',
    () {
      final workspace = _workspace();

      final target = workspaceEditorDiffTargetForFile(
        workspace: workspace,
        filePath: 'lib/main.dart',
        sourceControlScope: null,
      );

      expect(target, isNotNull);
      expect(target!.gitPath, workspace.path);
      expect(target.gitFilePath, 'lib/main.dart');
      expect(target.gitDiffRoot, isNull);
    },
  );
}

Workspace _workspace() {
  final now = DateTime(2026, 6, 6);
  return Workspace(
    id: 'ws-1',
    projectId: 'project-1',
    name: 'alera',
    path: '/repo/alera',
    createdAt: now,
    updatedAt: now,
    kind: .main,
    status: .active,
  );
}

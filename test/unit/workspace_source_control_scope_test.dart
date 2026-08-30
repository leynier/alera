import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('normalizes workspace paths without trimming significant spaces', () {
    expect(
      normalizeWorkspaceRelativePath('packages/app/lib/main.dart '),
      'packages/app/lib/main.dart ',
    );
    expect(
      normalizeSourceControlRootRelativePath(' packages/app'),
      ' packages/app',
    );
  });

  test('rejects empty and escaping workspace paths', () {
    expect(normalizeWorkspaceRelativePath(null), isNull);
    expect(normalizeWorkspaceRelativePath(''), isNull);
    expect(normalizeWorkspaceRelativePath('.'), isNull);
    expect(normalizeWorkspaceRelativePath('..'), isNull);
    expect(normalizeWorkspaceRelativePath('../outside'), isNull);
    expect(normalizeWorkspaceRelativePath('/outside'), isNull);
  });

  test('converts focused root paths while preserving file name spaces', () {
    const scope = WorkspaceSourceControlScope(
      workspaceId: 'workspace-1',
      workspacePath: '/repo/alera',
      path: '/repo/alera/packages/app',
      relativeRoot: 'packages/app',
    );

    expect(
      scope.toSourceRelativePath('packages/app/lib/main.dart '),
      'lib/main.dart ',
    );
    expect(
      scope.toWorkspaceRelativePath('lib/main.dart '),
      'packages/app/lib/main.dart ',
    );
  });

  test('resolves repository roots and configured folder roots', () {
    final now = DateTime.utc(2026, 7, 16);
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: 'project-1',
      name: 'Workspace',
      path: '/repo/alera',
      createdAt: now,
      updatedAt: now,
      kind: .main,
      status: .active,
    );
    final repository = Project(
      id: 'project-1',
      name: 'Alera',
      repoPath: '/repo/alera',
      createdAt: now,
      updatedAt: now,
    );
    final folder = repository.copyWith(kind: .folder);

    final repositoryScope = WorkspaceSourceControlScope.resolve(
      project: repository,
      workspace: workspace,
      prefs: .defaults,
    );
    expect(repositoryScope?.isWorkspaceRoot, isTrue);
    expect(repositoryScope?.displayPath, isEmpty);

    final folderScope = WorkspaceSourceControlScope.resolve(
      project: folder,
      workspace: workspace,
      prefs: WorkbenchViewPrefs.defaults.copyWith(
        sourceControlRootByWorkspaceId: const <String, String>{
          'workspace-1': 'packages/app',
        },
      ),
    );
    expect(folderScope?.path, p.join('/repo/alera', 'packages', 'app'));
    expect(folderScope?.displayPath, 'packages/app');
    expect(
      WorkspaceSourceControlScope.resolve(
        project: folder,
        workspace: workspace,
        prefs: .defaults,
      ),
      isNull,
    );
    expect(
      WorkspaceSourceControlScope.resolve(
        project: null,
        workspace: workspace,
        prefs: .defaults,
      ),
      isNull,
    );
  });

  test('maps root, outside, and null relative paths', () {
    const root = WorkspaceSourceControlScope(
      workspaceId: 'workspace-1',
      workspacePath: '/repo',
      path: '/repo',
    );
    const nested = WorkspaceSourceControlScope(
      workspaceId: 'workspace-1',
      workspacePath: '/repo',
      path: '/repo/packages/app',
      relativeRoot: 'packages/app',
    );

    expect(root.toSourceRelativePath('lib/main.dart'), 'lib/main.dart');
    expect(root.toWorkspaceRelativePath('lib/main.dart'), 'lib/main.dart');
    expect(nested.toSourceRelativePath(null), isNull);
    expect(nested.toSourceRelativePath('packages/app'), isEmpty);
    expect(nested.toSourceRelativePath('packages/other/file.dart'), isNull);
    expect(nested.toWorkspaceRelativePath(null), isNull);
    expect(nested.toWorkspaceRelativePath(''), 'packages/app');
  });
}

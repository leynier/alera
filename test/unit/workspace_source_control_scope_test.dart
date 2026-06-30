import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

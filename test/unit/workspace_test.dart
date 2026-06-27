import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses workspaces from json', () {
    final workspace = Workspace.fromJson(<String, Object?>{
      'id': 'workspace-1',
      'projectId': 'project-1',
      'name': 'Main',
      'branch': 'main',
      'path': '/repo/alera',
      'createdAt': '2026-05-25T12:00:00.000Z',
      'updatedAt': '2026-05-25T12:00:00.000Z',
      'kind': 'main',
      'status': 'active',
      'sourceBranch': 'origin/main',
      'reusesExistingBranch': true,
    });

    expect(workspace.id, 'workspace-1');
    expect(workspace.projectId, 'project-1');
    expect(workspace.branch, 'main');
    expect(workspace.kind, WorkspaceKind.main);
    expect(workspace.status, WorkspaceStatus.active);
    expect(workspace.sourceBranch, 'origin/main');
    expect(workspace.reusesExistingBranch, isTrue);
    expect(workspace.isMain, isTrue);
    expect(workspace.isActive, isTrue);
  });

  test('defaults reused branch metadata to false', () {
    final workspace = Workspace.fromJson(<String, Object?>{
      'id': 'workspace-1',
      'projectId': 'project-1',
      'name': 'Main',
      'branch': 'main',
      'path': '/repo/alera',
      'createdAt': '2026-05-25T12:00:00.000Z',
      'updatedAt': '2026-05-25T12:00:00.000Z',
      'kind': 'main',
      'status': 'active',
    });

    expect(workspace.reusesExistingBranch, isFalse);
  });
}

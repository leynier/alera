import 'package:alera/src/features/runs/presentation/run_remote_workspaces_notice.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

Workspace _workspace(String hostId) {
  final now = DateTime.utc(2026, 10, 11);
  return Workspace(
    id: 'ws-$hostId',
    projectId: 'proj-1',
    name: 'Workspace',
    path: '/tmp/ws',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.linked,
    status: .active,
    hostId: hostId,
  );
}

void main() {
  test('the notice appears only when a remote workspace was filtered', () {
    expect(hidesRemoteWorkspaces(const <Workspace>[]), isFalse);
    expect(
      hidesRemoteWorkspaces(<Workspace>[_workspace('local'), _workspace('')]),
      isFalse,
    );
    expect(
      hidesRemoteWorkspaces(<Workspace>[
        _workspace('local'),
        _workspace('build-box'),
      ]),
      isTrue,
    );
  });

  test('the notice names This Device rather than the runtime internals', () {
    expect(
      runRemoteWorkspacesNoticeMessage,
      'Runs use workspaces on This Device. Remote workspaces are not listed.',
    );
  });
}

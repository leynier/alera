part of 'workspace_service_test.dart';

void _registerWorkspaceServiceRemoteHostTests() {
  test(
    'createLinkedWorkspace refuses a remote host without a runtime host',
    () async {
      await expectLater(
        service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/remote',
          hostId: 'ssh-box',
        ),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.toString(),
            'message',
            contains('runtime host'),
          ),
        ),
      );
      expect(gitBackend.calls, isEmpty);
    },
  );
}

import 'package:alera/src/shared/infra/git/host_routed_git_backend.dart';
import 'package:alera/src/shared/infra/git/remote_checkout_index.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git_backend.dart';

void main() {
  group('RemoteCheckoutIndex', () {
    test('routes a path inside a remote checkout to its workspace', () {
      final index = RemoteCheckoutIndex(
        const [
          RemoteCheckoutEntry(workspaceId: 'ws-remote', path: '/srv/repo'),
        ],
        const ['/home/me/repo'],
      );

      expect(index.remoteWorkspaceIdFor('/srv/repo'), 'ws-remote');
      expect(index.remoteWorkspaceIdFor('/srv/repo/packages/app'), 'ws-remote');
      expect(index.remoteWorkspaceIdFor('/srv/repository'), isNull);
      expect(index.remoteWorkspaceIdFor('/home/me/repo'), isNull);
    });

    test('a local checkout with the same path wins', () {
      final index = RemoteCheckoutIndex(
        const [
          RemoteCheckoutEntry(workspaceId: 'ws-remote', path: '/home/me/repo'),
        ],
        const ['/home/me/repo'],
      );

      expect(index.remoteWorkspaceIdFor('/home/me/repo/src'), isNull);
    });

    test('the deepest remote checkout wins', () {
      final index = RemoteCheckoutIndex(const [
        RemoteCheckoutEntry(workspaceId: 'ws-outer', path: '/srv/repo'),
        RemoteCheckoutEntry(workspaceId: 'ws-inner', path: '/srv/repo/wt'),
      ], const []);

      expect(index.remoteWorkspaceIdFor('/srv/repo/wt/src'), 'ws-inner');
      expect(index.remoteWorkspaceIdFor('/srv/repo/src'), 'ws-outer');
    });

    test('Windows checkouts compare with Windows rules on any hub', () {
      final index = RemoteCheckoutIndex(
        const [
          RemoteCheckoutEntry(workspaceId: 'ws-win', path: r'C:\Users\me\repo'),
        ],
        const ['/home/me/repo'],
      );

      expect(index.remoteWorkspaceIdFor(r'C:\Users\me\repo\src'), 'ws-win');
      expect(index.remoteWorkspaceIdFor(r'c:/users/ME/repo'), 'ws-win');
      expect(index.remoteWorkspaceIdFor(r'C:\Users\me\repository'), isNull);
      expect(index.remoteWorkspaceIdFor('/srv/other'), isNull);
    });

    test('an empty index routes nothing', () {
      expect(
        const RemoteCheckoutIndex.empty().remoteWorkspaceIdFor('/srv/repo'),
        isNull,
      );
    });
  });

  group('HostRoutedGitBackend', () {
    test('sends path-bound calls to the resolved backend', () async {
      final local = FakeGitBackend();
      final remote = FakeGitBackend();
      final backend = HostRoutedGitBackend(
        local: local,
        remoteFor: (path) => path.startsWith('/srv/') ? remote : null,
      );

      await backend.status('/srv/repo');
      await backend.status('/home/me/repo');
      await backend.listBranches('/srv/repo');
      await backend.isValidBranchName('feature/x');

      expect(
        remote.calls.map((call) => call.method),
        containsAll(<String>['status', 'listBranches']),
      );
      expect(
        remote.calls
            .where((call) => call.method == 'status')
            .single
            .args['path'],
        '/srv/repo',
      );
      expect(
        local.calls
            .where((call) => call.method == 'status')
            .single
            .args['path'],
        '/home/me/repo',
      );
      expect(
        local.calls.any((call) => call.method == 'isValidBranchName'),
        isTrue,
      );
      expect(
        remote.calls.any((call) => call.method == 'isValidBranchName'),
        isFalse,
      );
    });
  });
}

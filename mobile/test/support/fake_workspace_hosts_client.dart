import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host.dart';

import 'fake_terminal_client.dart';

/// [FakeTerminalClient] for a runtime that may advertise
/// `mobileRemoteWorkspacesV1`. `listWorkspaceHosts` is recorded in [calls].
class FakeRemoteWorkspacesClient extends FakeTerminalClient
    implements MobileWorkspaceHostsClient {
  bool remoteWorkspacesSupported = true;
  Object? workspaceHostsError;
  List<MobileWorkspaceHost> workspaceHosts = const <MobileWorkspaceHost>[
    MobileWorkspaceHost(id: 'ssh-mac', alias: 'Studio Mac', platform: 'darwin'),
    MobileWorkspaceHost(id: 'ssh-win', alias: 'Build Box', platform: 'win32'),
    MobileWorkspaceHost(id: 'ssh-tux', alias: 'Rack', platform: 'linux'),
    MobileWorkspaceHost(id: 'ssh-bsd', alias: 'Attic', platform: 'freebsd'),
  ];

  @override
  bool get supportsRemoteWorkspaces => remoteWorkspacesSupported;

  @override
  Future<List<MobileWorkspaceHost>> listWorkspaceHosts() async {
    calls.add('listWorkspaceHosts');
    final failure = workspaceHostsError;
    if (failure != null) {
      throw failure;
    }
    return workspaceHosts;
  }
}

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host_status.dart';

import 'fake_terminal_client.dart';

/// [FakeTerminalClient] for a runtime that may advertise
/// `mobileRemoteWorkspacesV1`. `listWorkspaceHosts` is recorded in [calls].
class FakeRemoteWorkspacesClient extends FakeTerminalClient
    implements MobileWorkspaceHostsClient {
  bool remoteWorkspacesSupported = true;
  Object? workspaceHostsError;
  List<MobileWorkspaceHost> workspaceHosts = legacyWorkspaceHosts;

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

/// Hosts as a runtime that predates `status` names them.
const legacyWorkspaceHosts = <MobileWorkspaceHost>[
  MobileWorkspaceHost(id: 'ssh-mac', alias: 'Studio Mac', platform: 'darwin'),
  MobileWorkspaceHost(id: 'ssh-win', alias: 'Build Box', platform: 'win32'),
  MobileWorkspaceHost(id: 'ssh-tux', alias: 'Rack', platform: 'linux'),
  MobileWorkspaceHost(id: 'ssh-bsd', alias: 'Attic', platform: 'freebsd'),
];

/// One host per state `mobile.hosts.list` can report, for tests that assign
/// [FakeRemoteWorkspacesClient.workspaceHosts].
const statusWorkspaceHosts = <MobileWorkspaceHost>[
  MobileWorkspaceHost(
    id: 'ssh-mac',
    alias: 'Studio Mac',
    platform: 'darwin',
    status: MobileWorkspaceHostStatus.connected,
    runtimeVersion: '0.104.0',
    updateAvailable: true,
  ),
  MobileWorkspaceHost(
    id: 'ssh-win',
    alias: 'Build Box',
    platform: 'win32',
    status: MobileWorkspaceHostStatus.offline,
  ),
  MobileWorkspaceHost(
    id: 'ssh-tux',
    alias: 'Rack',
    platform: 'linux',
    status: MobileWorkspaceHostStatus.needsSetup,
  ),
  MobileWorkspaceHost(
    id: 'ssh-bsd',
    alias: 'Attic',
    platform: 'freebsd',
    status: MobileWorkspaceHostStatus.installing,
  ),
  MobileWorkspaceHost(
    id: 'ssh-lab',
    alias: 'Lab',
    platform: 'linux',
    status: MobileWorkspaceHostStatus.error,
  ),
];

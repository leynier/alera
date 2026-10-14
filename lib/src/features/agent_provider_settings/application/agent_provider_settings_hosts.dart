import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_provider_settings_hosts.g.dart';

/// One host the Providers pane can manage. [hostId] is null for This Device.
class const AgentProviderHostOption({
  required final String? hostId,
  required final String label,
  final HostOs os = HostOs.unknown,

  /// The host's link state when it is not plainly reachable, such as
  /// `Offline`; null for This Device and connected hosts.
  final String? statusLabel,
});

/// This Device first, then every Remote Host with an installed runtime, in
/// the order Remote Hosts lists them. A host that is offline stays listed
/// because the hub connects on demand; its state is shown beside its name.
@riverpod
List<AgentProviderHostOption> agentProviderHostOptions(Ref ref) {
  final hosts = ref.watch(remoteHostsControllerProvider).hosts;
  return <AgentProviderHostOption>[
    const AgentProviderHostOption(hostId: null, label: 'This Device'),
    for (final host in hosts)
      if (host.status.isReady)
        AgentProviderHostOption(
          hostId: host.id,
          label: host.alias,
          os: host.os,
          statusLabel: host.status is RemoteHostConnected
              ? null
              : host.status.label,
        ),
  ];
}

/// The host the pane opens on: the requested one when it is listed, else the
/// active workspace's host when it is listed, else This Device.
String? agentProviderInitialHost({
  required List<AgentProviderHostOption> options,
  String? requestedHostId,
  String? activeWorkspaceHostId,
}) {
  bool listed(String? hostId) =>
      options.any((option) => option.hostId == hostId);
  final requested = normalizedRemoteHostId(requestedHostId);
  if (requested != null && listed(requested)) {
    return requested;
  }
  final active = normalizedRemoteHostId(activeWorkspaceHostId);
  if (active != null && listed(active)) {
    return active;
  }
  return null;
}

/// The active workspace's host id, normalized so This Device is null.
@riverpod
String? agentProviderActiveWorkspaceHost(Ref ref) => normalizedRemoteHostId(
  ref.watch(
    workbenchControllerProvider.select(
      (state) => state.activeWorkspace?.hostId,
    ),
  ),
);

/// Projects a default can be set for, by id and name, in sidebar order.
@riverpod
List<({String id, String name})> agentProviderProjects(Ref ref) =>
    <({String id, String name})>[
      for (final project in ref.watch(
        workbenchControllerProvider.select((state) => state.projects),
      ))
        (id: project.id, name: project.name),
    ];

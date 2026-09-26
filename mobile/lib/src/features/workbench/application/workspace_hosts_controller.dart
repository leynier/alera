import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_hosts_controller.g.dart';

/// The hosts that own workspaces on one paired runtime, refreshed on
/// `sshTargetsChanged`. A failed load keeps the last directory, and a first
/// load that fails still marks remote workspaces under their raw host id.
@riverpod
class WorkspaceHostsController extends _$WorkspaceHostsController {
  @override
  Future<MobileWorkspaceHostDirectory> build(String hostId) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    if (client is! MobileWorkspaceHostsClient) {
      return const MobileWorkspaceHostDirectory();
    }
    final hosts = client as MobileWorkspaceHostsClient;
    if (!hosts.supportsRemoteWorkspaces) {
      return const MobileWorkspaceHostDirectory();
    }
    if (ref.mounted) {
      final subscription = client.events.listen((event) {
        if (ref.mounted && event.name == 'sshTargetsChanged') {
          ref.invalidateSelf();
        }
      });
      ref.onDispose(subscription.cancel);
    }
    try {
      final listed = await hosts.listWorkspaceHosts();
      return MobileWorkspaceHostDirectory(
        supported: true,
        byId: <String, MobileWorkspaceHost>{
          for (final host in listed) host.id: host,
        },
      );
    } on Object catch (error, stackTrace) {
      Logger('WorkspaceHostsController')
          .warning('Could not load workspace hosts', error, stackTrace);
      return state.value ?? const MobileWorkspaceHostDirectory(supported: true);
    }
  }
}

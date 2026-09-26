import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

/// A machine other than the paired runtime that owns workspaces, as named by
/// `mobile.hosts.list`. The runtime deliberately leaves out how to reach it.
class const MobileWorkspaceHost({
  required final String id,
  required final String alias,
  final String? platform,
}) {
  HostOs get os => HostOs.parse(platform);

  /// Mirrors the desktop `workspaceHostTooltip`.
  String get label => os == HostOs.unknown ? alias : '$alias (${os.label})';

  factory fromJson(Map<String, Object?> json) {
    final id = json.requiredString('id');
    return MobileWorkspaceHost(
      id: id,
      alias: json.optionalString('alias') ?? id,
      platform: json.optionalString('platform'),
    );
  }
}

/// The hosts one paired runtime can name. [supported] is false on a runtime
/// without `mobileRemoteWorkspacesV1`, where rows keep showing no host marker.
class const MobileWorkspaceHostDirectory({
  final bool supported = false,
  final Map<String, MobileWorkspaceHost> byId =
      const <String, MobileWorkspaceHost>{},
}) {
  /// The host to mark [workspace] with, or null for a workspace on the paired
  /// runtime. A host the runtime no longer names keeps a marker under its raw
  /// id, so the row still says the workspace lives elsewhere.
  MobileWorkspaceHost? hostOf(WorkspaceSummary workspace) {
    if (!supported || !workspace.isRemote) {
      return null;
    }
    return byId[workspace.hostId] ??
        MobileWorkspaceHost(id: workspace.hostId, alias: workspace.hostId);
  }
}

abstract interface class MobileWorkspaceHostsClient {
  /// Whether the runtime names its hosts and forwards the panel verbs to the
  /// host that owns a workspace.
  bool get supportsRemoteWorkspaces;

  Future<List<MobileWorkspaceHost>> listWorkspaceHosts();
}

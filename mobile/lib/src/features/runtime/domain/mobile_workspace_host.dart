import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host_status.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

/// A machine other than the paired runtime that owns workspaces, as named by
/// `mobile.hosts.list`. The runtime deliberately leaves out how to reach it.
/// [status], [runtimeVersion] and [updateAvailable] are absent on an older
/// runtime, which leaves every host ready.
class const MobileWorkspaceHost({
  required final String id,
  required final String alias,
  final String? platform,
  final MobileWorkspaceHostStatus status = MobileWorkspaceHostStatus.unknown,
  final String? runtimeVersion,
  final bool updateAvailable = false,
}) {
  HostOs get os => HostOs.parse(platform);

  /// Mirrors the desktop `workspaceHostTooltip`.
  String get label => os == HostOs.unknown ? alias : '$alias (${os.label})';

  /// Whether a workspace can be created on this host right now.
  bool get isReady => status.isReady;

  /// Picker entry text: the alias, followed by the state whenever it is
  /// something other than connected. A pending runtime update never blocks,
  /// so it only shows on an otherwise quiet host.
  String get pickerLabel {
    final suffix = switch (status) {
      MobileWorkspaceHostStatus.connected ||
      MobileWorkspaceHostStatus.unknown =>
        updateAvailable ? 'Update Available' : null,
      _ => status.label,
    };
    return suffix == null ? alias : '$alias ($suffix)';
  }

  /// Sentence shown under the picker while this host is selected, or null
  /// when it is ready with nothing to explain. [blocksCreation] tells whether
  /// it explains a disabled Create.
  ({String message, bool blocksCreation})? get pickerNotice {
    return switch (status) {
      MobileWorkspaceHostStatus.needsSetup => (
        message:
            'The Alera runtime is not installed on $alias. Set it up from the desktop.',
        blocksCreation: true,
      ),
      MobileWorkspaceHostStatus.installing => (
        message: '$alias is still installing the Alera runtime.',
        blocksCreation: true,
      ),
      MobileWorkspaceHostStatus.error => (
        message: '$alias has a connection error. Check it from the desktop.',
        blocksCreation: true,
      ),
      MobileWorkspaceHostStatus.offline ||
      MobileWorkspaceHostStatus.disconnected ||
      MobileWorkspaceHostStatus.connecting => (
        message: 'Alera connects to $alias when the workspace needs it.',
        blocksCreation: false,
      ),
      MobileWorkspaceHostStatus.connected ||
      MobileWorkspaceHostStatus.unknown => null,
    };
  }

  factory fromJson(Map<String, Object?> json) {
    final id = json.requiredString('id');
    return MobileWorkspaceHost(
      id: id,
      alias: json.optionalString('alias') ?? id,
      platform: json.optionalString('platform'),
      status: MobileWorkspaceHostStatus.parse(json.optionalString('status')),
      runtimeVersion: json.optionalString('runtimeVersion'),
      updateAvailable: json['updateAvailable'] == true,
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
    if (!supported || !workspace.isOnRemoteHost) {
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

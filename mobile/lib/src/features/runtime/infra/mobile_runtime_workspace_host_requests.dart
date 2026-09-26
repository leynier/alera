import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host.dart';

mixin MobileRuntimeWorkspaceHostRequests implements MobileWorkspaceHostsClient {
  Set<String> get runtimeCapabilities;
  Future<List<Object?>> requestList(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]);

  @override
  bool get supportsRemoteWorkspaces =>
      runtimeCapabilities.contains(mobileRemoteWorkspacesCapability);

  @override
  Future<List<MobileWorkspaceHost>> listWorkspaceHosts() async {
    if (!supportsRemoteWorkspaces) {
      return const <MobileWorkspaceHost>[];
    }
    return <MobileWorkspaceHost>[
      for (final item in await requestList('mobile.hosts.list'))
        MobileWorkspaceHost.fromJson(asJsonMap(item)),
    ];
  }
}

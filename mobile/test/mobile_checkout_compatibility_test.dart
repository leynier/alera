import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_project_client.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_workspace_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy creation options and removal do not call unsupported RPCs',
    () async {
      final client = _Client();
      final options = await client.listProjectCheckouts('project');
      expect(options.single.hostId, 'local');
      expect(await client.projectRemovalDependencies('project'), isEmpty);
      expect(await client.removalDependencies('workspace'), isEmpty);
      expect(client.supportsSharedCheckoutWorkspaces, isFalse);
      expect(client.calls, isEmpty);
    },
  );

  test(
    'project location choices exclude linked and legacy-only owners',
    () async {
      final client = _Client()
        ..runtimeCapabilities.add(sharedCheckoutWorkspacesCapability)
        ..rows = [
          {'kind': 'project', 'hostId': 'local', 'path': '/repo'},
          {'kind': 'linked', 'hostId': 'local', 'path': '/linked'},
          {
            'kind': 'project',
            'hostId': 'ssh',
            'path': '/remote',
            'hostName': 'SSH',
          },
          {'kind': 'linked', 'hostId': 'legacy-owner', 'path': '/legacy'},
        ];
      final options = await client.listProjectCheckouts('project');
      expect(options.map((item) => item.hostId), ['local', 'ssh']);
      expect(client.calls, ['checkout.list']);
      expect(options.last.label, 'SSH');
    },
  );
}

class _Client with MobileRuntimeWorkspaceClient, MobileRuntimeProjectClient {
  @override
  final Set<String> runtimeCapabilities = {};
  final calls = <String>[];
  List<Object?> rows = [];

  @override
  Future<List<Object?>> requestList(
    String type, [
    Map<String, Object?> payload = const {},
  ]) async {
    calls.add(type);
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

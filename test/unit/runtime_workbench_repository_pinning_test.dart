import 'package:alera/src/features/workbench/infra/runtime_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RuntimeWorkbenchRepository maps workspace pin updates', () async {
    final client = _PinningRuntimeHostClient();
    final repository = RuntimeWorkbenchRepository(client);

    final workspace = await repository.setWorkspacePinned('workspace-1', true);

    expect(workspace.isPinned, isTrue);
    expect(client.type, 'workspace.setPinned');
    expect(client.payload, <String, Object?>{
      'id': 'workspace-1',
      'isPinned': true,
    });
  });
}

final class _PinningRuntimeHostClient implements RuntimeHostClient {
  String? type;
  Map<String, Object?>? payload;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    this.type = type;
    this.payload = payload;
    return <String, Object?>{
      'id': 'workspace-1',
      'instanceId': 'instance-workspace-1',
      'hostId': 'local',
      'projectId': 'project-1',
      'name': 'Feature',
      'branch': 'feature/pins',
      'path': '/tmp/workspace-1',
      'createdAt': '2026-07-16T00:00:00.000Z',
      'updatedAt': '2026-07-16T00:00:00.000Z',
      'kind': 'linked',
      'status': 'active',
      'sourceBranch': 'main',
      'reusesExistingBranch': false,
      'isPinned': true,
      'tagIds': <String>[],
      'tagNames': <String>[],
      'parentWorkspaceId': null,
      'childCount': 0,
    };
  }
}

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_workspace_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('managed removal closes live terminal sessions like desktop', () async {
    final client = _Client();
    await client.removeManagedWorkspace('workspace-1', deleteBranch: true);
    expect(client.type, 'workspace.removeManaged');
    expect(client.payload, {
      'id': 'workspace-1',
      'closeSessions': true,
      'deleteBranch': true,
    });
    expect(client.timeout, const Duration(minutes: 10));
  });

  test('shared removal also confirms closing live terminal sessions', () async {
    final client = _Client();
    await client.removeSharedWorkspace('task');
    expect(client.calls, [
      'workspace.bufferGuard.acquire',
      'workspace.removeShared',
      'workspace.bufferGuard.release',
    ]);
    expect(client.payloads['workspace.removeShared'], {
      'id': 'task',
      'closeSessions': true,
      'deleteBranch': false,
      'bufferGuardId': 'proof',
    });
  });
}

class _Client with MobileRuntimeWorkspaceClient {
  @override
  final Set<String> runtimeCapabilities = {};
  String? type;
  Map<String, Object?>? payload;
  Duration? timeout;
  final calls = <String>[];
  final payloads = <String, Map<String, Object?>>{};

  @override
  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    this.type = type;
    this.payload = payload;
    this.timeout = timeout;
    calls.add(type);
    payloads[type] = payload;
    if (type == 'workspace.bufferGuard.acquire') {
      return const {'guardId': 'proof', 'ready': true};
    }
    return const <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async => const {};

  @override
  Future<List<Object?>> requestList(
    String type, [
    Map<String, Object?> payload = const {},
  ]) async => const [];
}

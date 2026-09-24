import 'package:alera/src/features/workbench/infra/workspace_buffer_guard_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('waits for acknowledgements and sends the proof only to the approved operation', () async {
    final calls = <String>[];
    Future<Object?> request(
      String type,
      Map<String, Object?> payload,
      Duration? timeout,
    ) async {
      calls.add(type);
      if (type == 'workspace.bufferGuard.acquire') {
        expect(payload, {'id': 'task', 'operation': 'removeShared'});
        return {
          'guardId': 'proof',
          'ready': false,
          'pendingClients': 1,
          'disconnectedClients': 0,
          'blockers': [],
        };
      }
      if (type == 'workspace.bufferGuard.status') {
        return {'guardId': 'proof', 'ready': true};
      }
      if (type == 'workspace.removeShared') {
        expect(payload, {
          'id': 'task',
          'closeSessions': true,
          'bufferGuardId': 'proof',
        });
        return {'id': 'task'};
      }
      expect(type, 'workspace.bufferGuard.release');
      return {};
    }

    final result = await requestWithWorkspaceBufferGuard(
      request: request,
      workspaceId: 'task',
      operation: 'removeShared',
      payload: {'id': 'task', 'closeSessions': true},
      timeout: const Duration(minutes: 10),
    );
    expect(result, {'id': 'task'});
    expect(calls, [
      'workspace.bufferGuard.acquire',
      'workspace.bufferGuard.status',
      'workspace.removeShared',
      'workspace.bufferGuard.release',
    ]);
  });

  for (final disconnected in [false, true]) {
    test(
      'refuses ${disconnected ? 'disconnected' : 'dirty'} clients and releases preparation',
      () async {
        final calls = <String>[];
        Future<Object?> request(
          String type,
          Map<String, Object?> payload,
          Duration? timeout,
        ) async {
          calls.add(type);
          if (type == 'workspace.bufferGuard.acquire') {
            return {
              'guardId': 'proof',
              'ready': false,
              'pendingClients': 0,
              'disconnectedClients': disconnected ? 1 : 0,
              'blockers': disconnected
                  ? []
                  : [
                      {'path': 'notes.md', 'reason': 'Unsaved changes'},
                    ],
            };
          }
          expect(type, 'workspace.bufferGuard.release');
          return {};
        }

        await expectLater(
          requestWithWorkspaceBufferGuard(
            request: request,
            workspaceId: 'task',
            operation: 'removeShared',
            payload: {'id': 'task'},
            timeout: const Duration(minutes: 10),
          ),
          throwsStateError,
        );
        expect(calls, [
          'workspace.bufferGuard.acquire',
          'workspace.bufferGuard.release',
        ]);
      },
    );
  }
}

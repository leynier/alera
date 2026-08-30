import 'dart:async';

import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeBrowserRuntimeHostClient implements RuntimeHostClient {
  final StreamController<RuntimeHostEvent> events =
      StreamController<RuntimeHostEvent>.broadcast(sync: true);
  final List<String> types = <String>[];
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  var generation = 1;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    types.add(type);
    payloads.add(Map<String, Object?>.from(payload));
    return switch (type) {
      'browser.driver.register' => <String, Object?>{
        'ok': true,
        'registered': true,
      },
      'browser.driver.sync' => <String, Object?>{
        'ok': true,
        'pages': <Map<String, Object?>>[
          for (final page in payload['pages']! as List<Object?>)
            <String, Object?>{
              'accepted': true,
              'pageId': (page! as Map<Object?, Object?>)['pageId'],
              'generation': generation,
            },
        ],
      },
      'browser.driver.pageChanged' => <String, Object?>{
        'ok': true,
        'page': <String, Object?>{
          'generation': payload['documentChanged'] == true
              ? ++generation
              : generation,
        },
        'preservedNavigationCorrelationId': payload['navigationCorrelationId'],
      },
      'browser.driver.complete' => <String, Object?>{
        'ok': true,
        'accepted': true,
      },
      'browser.driver.unregister' => <String, Object?>{
        'ok': true,
        'unregistered': true,
      },
      _ => throw StateError('Unexpected request: $type'),
    };
  }

  Future<void> dispose() => events.close();
}

Future<void> waitForBrowserRuntime(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not reached.');
}

WorkspaceTabRecord browserRuntimeTestTab() {
  return WorkspaceTabRecord(
    id: 'page-1',
    workspaceId: 'workspace-1',
    kind: .browser,
    title: 'New Tab',
    createdAt: .utc(2026),
    updatedAt: .utc(2026),
    payload: const <String, Object?>{
      workspaceTabBrowserProfileIdPayloadKey: 'default',
    },
  );
}

import 'dart:async';

import 'package:alera/src/features/workbench/infra/runtime_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('follows the slept terminals the host records', () async {
    var slept = <String, Object?>{
      'w1': <Object?>['t1', 3],
    };
    final host = _FakeRuntimeHostClient(
      capabilities: <String>{aleraRuntimeHostWorkspaceSleepStateCapability},
      respond: (type) => type == 'workspace.sleptTabs' ? slept : null,
    );
    final snapshots = <Map<String, List<String>>>[];
    final subscription = RuntimeWorkbenchRepository(
      host,
      coalescer: RuntimeChangeCoalescer(
        debounce: Duration.zero,
        maxDelay: Duration.zero,
      ),
    ).watchSleptWorkspaceTabs().listen(snapshots.add);
    await pumpEventQueue();

    slept = <String, Object?>{};
    host.emit(
      const RuntimeHostEvent('workspaceSleepChanged', <String, Object?>{}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pumpEventQueue();
    await subscription.cancel();

    expect(snapshots, <Map<String, List<String>>>[
      <String, List<String>>{
        'w1': <String>['t1'],
      },
      <String, List<String>>{},
    ]);
  });

  test('never asks a host without the sleep state capability', () async {
    final host = _FakeRuntimeHostClient(
      capabilities: const <String>{},
      respond: (_) => throw StateError('unknown request'),
    );
    final first = await RuntimeWorkbenchRepository(host)
        .watchSleptWorkspaceTabs()
        .first;

    expect(first, isEmpty);
    expect(host.requests, isEmpty);
  });
}

class _FakeRuntimeHostClient
    implements RuntimeHostClient, RuntimeHostCapabilityClient {
  _FakeRuntimeHostClient({required this.capabilities, required this.respond});

  final Set<String> capabilities;
  final Object? Function(String type) respond;
  final List<String> requests = <String>[];
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();

  void emit(RuntimeHostEvent event) => _events.add(event);

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add(type);
    return respond(type);
  }

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      capabilities.contains(capability);
}

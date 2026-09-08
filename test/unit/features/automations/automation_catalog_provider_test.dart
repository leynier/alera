import 'dart:async';

import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeRuntimeHostClient client;
  late ProviderContainer container;

  setUp(() {
    client = _FakeRuntimeHostClient();
    container = ProviderContainer(
      overrides: [
        automationRepositoryProvider.overrideWithValue(
          RuntimeAutomationRepository(client),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    client.dispose();
  });

  test(
    'trash catalog keeps trashed items after automationsChanged events',
    () async {
      final ids = <List<String>>[];
      container.listen(automationCatalogProvider(true), (_, next) {
        next.whenData(
          (items) => ids.add(items.map((item) => item.id).toList()),
        );
      });

      await Future.pause(const Duration(milliseconds: 20));
      expect(ids, isNotEmpty);
      expect(ids.first, <String>['active-1', 'trashed-1']);

      client.addEvent(
        const RuntimeHostEvent('automationsChanged', <String, Object?>{}),
      );
      await Future.pause(const Duration(milliseconds: 20));
      client.addEvent(
        const RuntimeHostEvent('automationRunChanged', <String, Object?>{}),
      );
      await Future.pause(const Duration(milliseconds: 20));

      expect(ids, hasLength(3));
      expect(
        ids.every((emission) => emission.contains('trashed-1')),
        isTrue,
        reason: 'watch() must keep includeTrashed on every catalog emission',
      );
      expect(client.listIncludeTrashed, <bool>[true, true, true]);
    },
  );

  test('default catalog omits trashed automations', () async {
    container.listen(automationCatalogProvider(false), (_, _) {});
    await Future.pause(const Duration(milliseconds: 20));

    expect(
      container
          .read(automationCatalogProvider(false))
          .requireValue
          .map((item) => item.id),
      <String>['active-1'],
    );
    expect(client.listIncludeTrashed, <bool>[false]);
  });

  test(
    'retrying invalidates the catalog, not the unused list provider',
    () async {
      client.failNextList = 1;
      container.listen(automationCatalogProvider(true), (_, _) {});
      await Future.pause(const Duration(milliseconds: 20));

      expect(container.read(automationCatalogProvider(true)).hasError, isTrue);

      container.invalidate(automationListProvider);
      await Future.pause(const Duration(milliseconds: 20));
      expect(
        container.read(automationCatalogProvider(true)).hasError,
        isTrue,
        reason: 'Retry used to invalidate automationListProvider, which the dialog does not watch',
      );

      container.invalidate(automationCatalogProvider(true));
      await Future.pause(const Duration(milliseconds: 20));

      final retry = container.read(automationCatalogProvider(true));
      expect(retry.hasValue, isTrue);
      expect(retry.requireValue.map((item) => item.id), contains('trashed-1'));
    },
  );
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  int failNextList = 0;
  final List<bool> listIncludeTrashed = <bool>[];
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  void addEvent(RuntimeHostEvent event) => _events.add(event);

  void dispose() => unawaited(_events.close());

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    if (type != 'automation.list') {
      fail('unexpected runtime request: $type');
    }
    if (failNextList > 0) {
      failNextList -= 1;
      throw StateError('host unavailable');
    }
    final includeTrashed = payload['includeTrashed'] == true;
    listIncludeTrashed.add(includeTrashed);
    return <String, Object?>{
      'items': <Object?>[
        _record('active-1', 'Nightly Review', 'active'),
        if (includeTrashed) _record('trashed-1', 'Trashed Draft', 'trashed'),
      ],
    };
  }
}

Map<String, Object?> _record(String id, String name, String state) {
  return <String, Object?>{
    'id': id,
    'slug': id,
    'name': name,
    'state': state,
    'revision': 1,
    'schedule': const <String, Object?>{'oneTime': '2026-09-08T12:00:00Z'},
    'target': const <String, Object?>{'freshTab': true},
  };
}

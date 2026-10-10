import 'package:alera/src/features/webhooks/domain/runtime_webhook.dart';
import 'package:alera/src/features/webhooks/domain/webhook_repository.dart';
import 'package:alera/src/features/webhooks/infra/runtime_webhook_repository.dart';
import 'package:alera/src/features/webhooks/presentation/webhook_list_row.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _webhookJson({
  String id = 'wh_1',
  List<String>? kinds,
  Object? lastDeliveryAt = '2026-10-09T12:00:00Z',
  String? lastError,
}) {
  return <String, Object?>{
    'id': id,
    'url': 'https://example.com/hooks',
    'kinds':
        kinds ??
        <String>[for (final kind in RuntimeEventKind.values) kind.wireName],
    'runtimeIds': <String>[],
    'allRuntimes': true,
    'status': 'active',
    'createdAt': '2026-10-01T08:00:00Z',
    'lastDeliveryAt': lastDeliveryAt,
    'lastError': lastError,
  };
}

void main() {
  test('supportsWebhooks reads runtimeEventsV1 from status.get', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['status.get'] = <String, Object?>{
        'runtimeCapabilities': <String>['runSurfacesV1', 'runtimeEventsV1'],
      };
    final repository = RuntimeWebhookRepository(client);

    expect(await repository.supportsWebhooks(), isTrue);
    expect(client.calls.single.type, 'status.get');

    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': <String>['runSurfacesV1'],
    };
    expect(await repository.supportsWebhooks(), isFalse);

    client.responses['status.get'] = const <String, Object?>{};
    expect(await repository.supportsWebhooks(), isFalse);
  });

  test('lists webhooks and skips malformed entries', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['webhook.list'] = <String, Object?>{
        'webhooks': <Object?>[
          _webhookJson(lastError: 'HTTP 500'),
          'garbage',
          _webhookJson(
            id: 'wh_2',
            kinds: <String>['agent.status', 'terminal.exit'],
            lastDeliveryAt: null,
          ),
        ],
      };
    final repository = RuntimeWebhookRepository(client);

    final webhooks = await repository.listWebhooks();

    expect(client.calls.single.type, 'webhook.list');
    expect(client.calls.single.payload, isEmpty);
    expect(webhooks, hasLength(2));
    final first = webhooks.first;
    expect(first.id, 'wh_1');
    expect(first.url, 'https://example.com/hooks');
    expect(first.status, 'active');
    expect(first.allRuntimes, isTrue);
    expect(first.receivesAllKinds, isTrue);
    expect(first.createdAt, DateTime.utc(2026, 10, 1, 8));
    expect(first.lastDeliveryAt, DateTime.utc(2026, 10, 9, 12));
    expect(first.lastError, 'HTTP 500');
    expect(webhookKindsSummary(first), 'All Events');

    final second = webhooks.last;
    expect(second.receivesAllKinds, isFalse);
    expect(second.lastDeliveryAt, isNull);
    expect(second.lastError, isNull);
    expect(webhookKindsSummary(second), 'Agent Status, Terminal Exit');
    expect(webhookDeliveryDetail(second), startsWith('No deliveries yet'));
  });

  test('reads epoch seconds and milliseconds as UTC dates', () {
    final seconds = RuntimeWebhook.fromJson(
      _webhookJson(lastDeliveryAt: 1791201600),
    );
    final millis = RuntimeWebhook.fromJson(
      _webhookJson(lastDeliveryAt: 1791201600000),
    );

    expect(seconds.lastDeliveryAt, DateTime.utc(2026, 10, 5, 12));
    expect(millis.lastDeliveryAt, DateTime.utc(2026, 10, 5, 12));
  });

  test('rejects a webhook without an id or url', () {
    expect(
      () => RuntimeWebhook.fromJson(const <String, Object?>{'id': 'wh'}),
      throwsFormatException,
    );
    expect(
      () => RuntimeWebhook.fromJson(const <String, Object?>{
        'url': 'https://example.com',
      }),
      throwsFormatException,
    );
  });

  test('create sends the url and omits kinds when all are wanted', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['webhook.create'] = <String, Object?>{
        'webhook': _webhookJson(),
        'secret': 'whsec_abc',
      };
    final repository = RuntimeWebhookRepository(client);

    final created = await repository.createWebhook(
      url: '  https://example.com/hooks  ',
    );

    expect(client.calls.single.type, 'webhook.create');
    expect(client.calls.single.payload, <String, Object?>{
      'url': 'https://example.com/hooks',
    });
    expect(created.secret, 'whsec_abc');
    expect(created.webhook.id, 'wh_1');

    await repository.createWebhook(
      url: 'https://example.com/hooks',
      kinds: <String>['inbox.reply'],
    );
    expect(client.calls.last.payload, <String, Object?>{
      'url': 'https://example.com/hooks',
      'kinds': <String>['inbox.reply'],
    });
  });

  test('create fails when the secret is missing', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['webhook.create'] = <String, Object?>{
        'webhook': _webhookJson(),
      };

    await expectLater(
      RuntimeWebhookRepository(client)
          .createWebhook(url: 'https://example.com/hooks'),
      throwsFormatException,
    );
  });

  test('delete and test send the webhook id', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['webhook.delete'] = <String, Object?>{
        'deleted': true,
        'id': 'wh_1',
      }
      ..responses['webhook.test'] = <String, Object?>{'deliveryId': 'dl_9'};
    final repository = RuntimeWebhookRepository(client);

    await repository.deleteWebhook('wh_1');
    final deliveryId = await repository.testWebhook('wh_1');

    expect(client.calls.map((call) => call.type), <String>[
      'webhook.delete',
      'webhook.test',
    ]);
    for (final call in client.calls) {
      expect(call.payload, <String, Object?>{'id': 'wh_1'});
    }
    expect(deliveryId, 'dl_9');
  });

  test('runtime errors surface as readable messages', () async {
    final client = _FakeRuntimeHostClient()
      ..error = StateError('Sign in to an Alera account first.');

    await expectLater(
      RuntimeWebhookRepository(client).listWebhooks(),
      throwsStateError,
    );
    expect(
      webhookErrorMessage(StateError('Sign in to an Alera account first.')),
      'Sign in to an Alera account first.',
    );
    expect(
      webhookErrorMessage(
        StateError('Unknown terminal host request: webhook.list'),
      ),
      'Update the Alera runtime to use webhooks.',
    );
  });

  test('validates webhook URLs', () {
    expect(webhookUrlError('https://example.com/hooks'), isNull);
    expect(webhookUrlError(''), isNotNull);
    expect(webhookUrlError('example.com'), isNotNull);
    expect(
      webhookUrlError('http://example.com/hooks'),
      'Webhook URLs must use https.',
    );
  });

  test('event kinds round-trip their wire names', () {
    expect(RuntimeEventKind.values, hasLength(11));
    for (final kind in RuntimeEventKind.values) {
      expect(RuntimeEventKind.fromWire(kind.wireName), kind);
    }
    expect(RuntimeEventKind.fromWire('made.up'), isNull);
  });
}

final class _Call(final String type, final Map<String, Object?> payload);

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  final Map<String, Object?> responses = <String, Object?>{};
  final List<_Call> calls = <_Call>[];
  Object? error;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    calls.add(_Call(type, Map<String, Object?>.from(payload)));
    if (error case final Object failure) {
      throw failure;
    }
    return responses[type];
  }
}

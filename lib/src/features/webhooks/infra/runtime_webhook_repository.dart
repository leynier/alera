import 'package:alera/src/features/webhooks/domain/runtime_webhook.dart';
import 'package:alera/src/features/webhooks/domain/webhook_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

final class RuntimeWebhookRepository(final RuntimeHostClient _client)
    implements WebhookRepository {
  @override
  Future<bool> supportsWebhooks() async {
    final status = _map(await _client.runtimeRequest('status.get'), 'status');
    final capabilities = status['runtimeCapabilities'];
    return capabilities is List &&
        capabilities.contains(runtimeEventsCapability);
  }

  @override
  Future<List<RuntimeWebhook>> listWebhooks() async {
    final payload = _map(await _client.runtimeRequest('webhook.list'), 'list');
    final webhooks = payload['webhooks'];
    return List<RuntimeWebhook>.unmodifiable(<RuntimeWebhook>[
      if (webhooks is List)
        for (final webhook in webhooks)
          if (webhook is Map)
            RuntimeWebhook.fromJson(Map<String, Object?>.from(webhook)),
    ]);
  }

  @override
  Future<RuntimeWebhookCreation> createWebhook({
    required String url,
    List<String>? kinds,
  }) async {
    final payload = await _client.runtimeRequest(
      'webhook.create',
      <String, Object?>{'url': url.trim(), 'kinds': ?kinds},
    );
    return RuntimeWebhookCreation.fromJson(_map(payload, 'creation'));
  }

  @override
  Future<void> deleteWebhook(String id) async {
    await _client.runtimeRequest('webhook.delete', <String, Object?>{'id': id});
  }

  @override
  Future<String> testWebhook(String id) async {
    final payload = _map(
      await _client.runtimeRequest('webhook.test', <String, Object?>{'id': id}),
      'test',
    );
    final deliveryId = payload['deliveryId'];
    return deliveryId is String ? deliveryId : '';
  }
}

Map<String, Object?> _map(Object? value, String label) {
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw FormatException('Runtime webhook $label payload must be an object.');
}

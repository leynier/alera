import 'package:alera/src/features/mcp_access/domain/mcp_access_error_message.dart';
import 'package:alera/src/features/webhooks/domain/runtime_webhook.dart';

/// Runtime event webhooks of the signed-in Alera account, managed through the
/// local runtime's `webhook.*` requests.
abstract interface class WebhookRepository {
  /// Whether the connected runtime advertises [runtimeEventsCapability].
  Future<bool> supportsWebhooks();

  Future<List<RuntimeWebhook>> listWebhooks();

  /// Omitting [kinds] subscribes the webhook to every event kind.
  Future<RuntimeWebhookCreation> createWebhook({
    required String url,
    List<String>? kinds,
  });

  Future<void> deleteWebhook(String id);

  /// Queues a test delivery and returns its delivery id.
  Future<String> testWebhook(String id);
}

/// Sentence-case text for a webhook request failure.
String webhookErrorMessage(Object error) {
  if (isUnsupportedMcpRequest(error)) {
    return 'Update the Alera runtime to use webhooks.';
  }
  return mcpAccessErrorMessage(error);
}

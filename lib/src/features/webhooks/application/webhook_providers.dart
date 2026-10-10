import 'package:alera/src/features/webhooks/domain/runtime_webhook.dart';
import 'package:alera/src/features/webhooks/domain/webhook_repository.dart';
import 'package:alera/src/features/webhooks/infra/runtime_webhook_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'webhook_providers.g.dart';

// The list has a Refresh action, so an automatic retry would only hide a
// failure behind a spinner.
Duration? _noWebhookRetry(int retryCount, Object error) => null;

@Riverpod(keepAlive: true)
WebhookRepository webhookRepository(Ref ref) =>
    RuntimeWebhookRepository(ref.watch(runtimeHostClientProvider));

/// Whether the connected runtime serves `webhook.*`, read each time the
/// settings page opens.
@Riverpod(retry: _noWebhookRetry)
Future<bool> webhooksSupported(Ref ref) =>
    ref.watch(webhookRepositoryProvider).supportsWebhooks();

/// Webhooks of the signed-in account, read each time the settings page opens.
@Riverpod(retry: _noWebhookRetry)
Future<List<RuntimeWebhook>> runtimeWebhooks(Ref ref) =>
    ref.watch(webhookRepositoryProvider).listWebhooks();

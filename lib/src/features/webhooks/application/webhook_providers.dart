import 'package:alera/src/features/webhooks/domain/runtime_webhook.dart';
import 'package:alera/src/features/webhooks/domain/webhook_repository.dart';
import 'package:alera/src/features/webhooks/infra/runtime_webhook_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The list has a Refresh action, so an automatic retry would only hide a
// failure behind a spinner.
Duration? _noWebhookRetry(int retryCount, Object error) => null;

final Provider<WebhookRepository> webhookRepositoryProvider =
    Provider<WebhookRepository>(
      (ref) => RuntimeWebhookRepository(ref.watch(runtimeHostClientProvider)),
    );

/// Whether the connected runtime serves `webhook.*`, read each time the
/// settings page opens.
final FutureProvider<bool> webhooksSupportedProvider =
    FutureProvider.autoDispose<bool>(
      (ref) => ref.watch(webhookRepositoryProvider).supportsWebhooks(),
      retry: _noWebhookRetry,
    );

/// Webhooks of the signed-in account, read each time the settings page opens.
final FutureProvider<List<RuntimeWebhook>> runtimeWebhooksProvider =
    FutureProvider.autoDispose<List<RuntimeWebhook>>(
      (ref) => ref.watch(webhookRepositoryProvider).listWebhooks(),
      retry: _noWebhookRetry,
    );

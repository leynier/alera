// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'webhook_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(webhookRepository)
final webhookRepositoryProvider = WebhookRepositoryProvider._();

final class WebhookRepositoryProvider
    extends
        $FunctionalProvider<
          WebhookRepository,
          WebhookRepository,
          WebhookRepository
        >
    with $Provider<WebhookRepository> {
  WebhookRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'webhookRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$webhookRepositoryHash();

  @$internal
  @override
  $ProviderElement<WebhookRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WebhookRepository create(Ref ref) {
    return webhookRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WebhookRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WebhookRepository>(value),
    );
  }
}

String _$webhookRepositoryHash() => r'a61ff08f30707c583baaa1fa7f7063f8b99e34ec';

/// Whether the connected runtime serves `webhook.*`, read each time the
/// settings page opens.

@ProviderFor(webhooksSupported)
final webhooksSupportedProvider = WebhooksSupportedProvider._();

/// Whether the connected runtime serves `webhook.*`, read each time the
/// settings page opens.

final class WebhooksSupportedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the connected runtime serves `webhook.*`, read each time the
  /// settings page opens.
  WebhooksSupportedProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noWebhookRetry,
        name: r'webhooksSupportedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$webhooksSupportedHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return webhooksSupported(ref);
  }
}

String _$webhooksSupportedHash() => r'4ddf795d47ba82325cd61928ec7ad03f461e5000';

/// Webhooks of the signed-in account, read each time the settings page opens.

@ProviderFor(runtimeWebhooks)
final runtimeWebhooksProvider = RuntimeWebhooksProvider._();

/// Webhooks of the signed-in account, read each time the settings page opens.

final class RuntimeWebhooksProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RuntimeWebhook>>,
          List<RuntimeWebhook>,
          FutureOr<List<RuntimeWebhook>>
        >
    with
        $FutureModifier<List<RuntimeWebhook>>,
        $FutureProvider<List<RuntimeWebhook>> {
  /// Webhooks of the signed-in account, read each time the settings page opens.
  RuntimeWebhooksProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noWebhookRetry,
        name: r'runtimeWebhooksProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeWebhooksHash();

  @$internal
  @override
  $FutureProviderElement<List<RuntimeWebhook>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<RuntimeWebhook>> create(Ref ref) {
    return runtimeWebhooks(ref);
  }
}

String _$runtimeWebhooksHash() => r'11b5a3185027eddbf79a2fc0da6dc5b5ccfff701';

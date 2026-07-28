// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_notification_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(pushMessagingService)
final pushMessagingServiceProvider = PushMessagingServiceProvider._();

final class PushMessagingServiceProvider
    extends
        $FunctionalProvider<
          PushMessagingService,
          PushMessagingService,
          PushMessagingService
        >
    with $Provider<PushMessagingService> {
  PushMessagingServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pushMessagingServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pushMessagingServiceHash();

  @$internal
  @override
  $ProviderElement<PushMessagingService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PushMessagingService create(Ref ref) {
    return pushMessagingService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PushMessagingService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PushMessagingService>(value),
    );
  }
}

String _$pushMessagingServiceHash() =>
    r'8788410aebaa07c6a5e760da192128f2568fd3e6';

@ProviderFor(mobileLocalNotificationService)
final mobileLocalNotificationServiceProvider =
    MobileLocalNotificationServiceProvider._();

final class MobileLocalNotificationServiceProvider
    extends
        $FunctionalProvider<
          MobileLocalNotificationService,
          MobileLocalNotificationService,
          MobileLocalNotificationService
        >
    with $Provider<MobileLocalNotificationService> {
  MobileLocalNotificationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileLocalNotificationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileLocalNotificationServiceHash();

  @$internal
  @override
  $ProviderElement<MobileLocalNotificationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MobileLocalNotificationService create(Ref ref) {
    return mobileLocalNotificationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileLocalNotificationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileLocalNotificationService>(
        value,
      ),
    );
  }
}

String _$mobileLocalNotificationServiceHash() =>
    r'5b9924274b2724f29d6c96eadf2eeee9f4ddc3d5';

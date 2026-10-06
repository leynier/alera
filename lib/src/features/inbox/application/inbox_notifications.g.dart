// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_notifications.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Shows a system notification when replies arrive while the inbox page is
/// hidden. The body never contains the reply text. The shell watches it for
/// its whole life, so it does not need `keepAlive`, which would forbid
/// listening to the auto-disposed unread count.

@ProviderFor(inboxReplyNotificationCoordinator)
final inboxReplyNotificationCoordinatorProvider =
    InboxReplyNotificationCoordinatorProvider._();

/// Shows a system notification when replies arrive while the inbox page is
/// hidden. The body never contains the reply text. The shell watches it for
/// its whole life, so it does not need `keepAlive`, which would forbid
/// listening to the auto-disposed unread count.

final class InboxReplyNotificationCoordinatorProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Shows a system notification when replies arrive while the inbox page is
  /// hidden. The body never contains the reply text. The shell watches it for
  /// its whole life, so it does not need `keepAlive`, which would forbid
  /// listening to the auto-disposed unread count.
  InboxReplyNotificationCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inboxReplyNotificationCoordinatorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$inboxReplyNotificationCoordinatorHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return inboxReplyNotificationCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$inboxReplyNotificationCoordinatorHash() =>
    r'a2b9acb5b165ace9e6c78a6ae50fe77c7c0943a2';

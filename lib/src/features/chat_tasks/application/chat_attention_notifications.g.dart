// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_attention_notifications.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Toasts and OS notifications for chats that start waiting, stop with an
/// error or finish, once per transition. A focused window gets a toast with
/// Open Chat unless that chat is the one on screen; an unfocused one gets an
/// OS notification when the person turned agent notifications on. Child
/// chats report through their parent. Nothing here selects a workspace or a
/// tab unless the person presses Open Chat.

@ProviderFor(chatAttentionNotificationCoordinator)
final chatAttentionNotificationCoordinatorProvider =
    ChatAttentionNotificationCoordinatorProvider._();

/// Toasts and OS notifications for chats that start waiting, stop with an
/// error or finish, once per transition. A focused window gets a toast with
/// Open Chat unless that chat is the one on screen; an unfocused one gets an
/// OS notification when the person turned agent notifications on. Child
/// chats report through their parent. Nothing here selects a workspace or a
/// tab unless the person presses Open Chat.

final class ChatAttentionNotificationCoordinatorProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Toasts and OS notifications for chats that start waiting, stop with an
  /// error or finish, once per transition. A focused window gets a toast with
  /// Open Chat unless that chat is the one on screen; an unfocused one gets an
  /// OS notification when the person turned agent notifications on. Child
  /// chats report through their parent. Nothing here selects a workspace or a
  /// tab unless the person presses Open Chat.
  ChatAttentionNotificationCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatAttentionNotificationCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$chatAttentionNotificationCoordinatorHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return chatAttentionNotificationCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$chatAttentionNotificationCoordinatorHash() =>
    r'52384a2433c9a76bb536e3a9781889e3040b388c';

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_workspace_attention.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every unarchived chat the runtime lists, across workspaces, so the sidebar
/// and attention notices see chats whose tab is not open. One `agentChat.list`
/// without a workspace seeds it; session and request changes fold in place,
/// and a list change, a settled turn, a deletion or a reconnect reads again.

@ProviderFor(ChatAttentionEntries)
final chatAttentionEntriesProvider = ChatAttentionEntriesProvider._();

/// Every unarchived chat the runtime lists, across workspaces, so the sidebar
/// and attention notices see chats whose tab is not open. One `agentChat.list`
/// without a workspace seeds it; session and request changes fold in place,
/// and a list change, a settled turn, a deletion or a reconnect reads again.
final class ChatAttentionEntriesProvider
    extends
        $NotifierProvider<
          ChatAttentionEntries,
          Map<String, ChatAttentionEntry>
        > {
  /// Every unarchived chat the runtime lists, across workspaces, so the sidebar
  /// and attention notices see chats whose tab is not open. One `agentChat.list`
  /// without a workspace seeds it; session and request changes fold in place,
  /// and a list change, a settled turn, a deletion or a reconnect reads again.
  ChatAttentionEntriesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatAttentionEntriesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatAttentionEntriesHash();

  @$internal
  @override
  ChatAttentionEntries create() => ChatAttentionEntries();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, ChatAttentionEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, ChatAttentionEntry>>(
        value,
      ),
    );
  }
}

String _$chatAttentionEntriesHash() =>
    r'eb61804d683606243846d297b5104dc1f4ea894c';

/// Every unarchived chat the runtime lists, across workspaces, so the sidebar
/// and attention notices see chats whose tab is not open. One `agentChat.list`
/// without a workspace seeds it; session and request changes fold in place,
/// and a list change, a settled turn, a deletion or a reconnect reads again.

abstract class _$ChatAttentionEntries
    extends $Notifier<Map<String, ChatAttentionEntry>> {
  Map<String, ChatAttentionEntry> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, ChatAttentionEntry>,
              Map<String, ChatAttentionEntry>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, ChatAttentionEntry>,
                Map<String, ChatAttentionEntry>
              >,
              Map<String, ChatAttentionEntry>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The chats with live child task counts merged in, since the runtime's list
/// only refreshes them on its next read. On a runtime without chat tasks the
/// list's own counts stand.

@ProviderFor(chatAttentionLive)
final chatAttentionLiveProvider = ChatAttentionLiveProvider._();

/// The chats with live child task counts merged in, since the runtime's list
/// only refreshes them on its next read. On a runtime without chat tasks the
/// list's own counts stand.

final class ChatAttentionLiveProvider
    extends
        $FunctionalProvider<
          Map<String, ChatAttentionEntry>,
          Map<String, ChatAttentionEntry>,
          Map<String, ChatAttentionEntry>
        >
    with $Provider<Map<String, ChatAttentionEntry>> {
  /// The chats with live child task counts merged in, since the runtime's list
  /// only refreshes them on its next read. On a runtime without chat tasks the
  /// list's own counts stand.
  ChatAttentionLiveProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatAttentionLiveProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatAttentionLiveHash();

  @$internal
  @override
  $ProviderElement<Map<String, ChatAttentionEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, ChatAttentionEntry> create(Ref ref) {
    return chatAttentionLive(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, ChatAttentionEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, ChatAttentionEntry>>(
        value,
      ),
    );
  }
}

String _$chatAttentionLiveHash() => r'98527055af12e49cb285539416f9f0121890d596';

/// What each workspace's chats want, for its sidebar row and the Agent
/// Activity sort. Workspaces whose chats are idle are absent.

@ProviderFor(chatWorkspaceAttention)
final chatWorkspaceAttentionProvider = ChatWorkspaceAttentionProvider._();

/// What each workspace's chats want, for its sidebar row and the Agent
/// Activity sort. Workspaces whose chats are idle are absent.

final class ChatWorkspaceAttentionProvider
    extends
        $FunctionalProvider<
          Map<String, ChatWorkspaceAttention>,
          Map<String, ChatWorkspaceAttention>,
          Map<String, ChatWorkspaceAttention>
        >
    with $Provider<Map<String, ChatWorkspaceAttention>> {
  /// What each workspace's chats want, for its sidebar row and the Agent
  /// Activity sort. Workspaces whose chats are idle are absent.
  ChatWorkspaceAttentionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatWorkspaceAttentionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatWorkspaceAttentionHash();

  @$internal
  @override
  $ProviderElement<Map<String, ChatWorkspaceAttention>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, ChatWorkspaceAttention> create(Ref ref) {
    return chatWorkspaceAttention(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, ChatWorkspaceAttention> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, ChatWorkspaceAttention>>(
        value,
      ),
    );
  }
}

String _$chatWorkspaceAttentionHash() =>
    r'43623ae9f43b7e35c57475e1772190551eb48f28';

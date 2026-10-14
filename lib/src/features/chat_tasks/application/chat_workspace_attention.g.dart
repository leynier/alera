// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_workspace_attention.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every unarchived chat the runtime lists, across workspaces, kept current
/// by the shared [AgentChatAttentionTracker].

@ProviderFor(ChatAttentionEntries)
final chatAttentionEntriesProvider = ChatAttentionEntriesProvider._();

/// Every unarchived chat the runtime lists, across workspaces, kept current
/// by the shared [AgentChatAttentionTracker].
final class ChatAttentionEntriesProvider
    extends
        $NotifierProvider<
          ChatAttentionEntries,
          Map<String, ChatAttentionEntry>
        > {
  /// Every unarchived chat the runtime lists, across workspaces, kept current
  /// by the shared [AgentChatAttentionTracker].
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
    r'f564180d08199ca49a6df0cb1fe3c23b8b3c319c';

/// Every unarchived chat the runtime lists, across workspaces, kept current
/// by the shared [AgentChatAttentionTracker].

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
        isAutoDispose: false,
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

String _$chatAttentionLiveHash() => r'd777fc23cf0db361c4d786dad256afc250609455';

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
        isAutoDispose: false,
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
    r'f2da9a1a6085fa3d515372d7916429f5a3d01818';

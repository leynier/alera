// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_chat_agent_presence.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every unarchived chat on [hostId], kept current by the same tracker the
/// desktop uses, so workspace rows can list chats beside terminal agents.
/// Empty against a runtime without agent chats.

@ProviderFor(MobileChatAttentionEntries)
final mobileChatAttentionEntriesProvider = MobileChatAttentionEntriesFamily._();

/// Every unarchived chat on [hostId], kept current by the same tracker the
/// desktop uses, so workspace rows can list chats beside terminal agents.
/// Empty against a runtime without agent chats.
final class MobileChatAttentionEntriesProvider
    extends
        $NotifierProvider<
          MobileChatAttentionEntries,
          Map<String, ChatAttentionEntry>
        > {
  /// Every unarchived chat on [hostId], kept current by the same tracker the
  /// desktop uses, so workspace rows can list chats beside terminal agents.
  /// Empty against a runtime without agent chats.
  MobileChatAttentionEntriesProvider._({
    required MobileChatAttentionEntriesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatAttentionEntriesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatAttentionEntriesHash();

  @override
  String toString() {
    return r'mobileChatAttentionEntriesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileChatAttentionEntries create() => MobileChatAttentionEntries();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, ChatAttentionEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, ChatAttentionEntry>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatAttentionEntriesProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatAttentionEntriesHash() =>
    r'084fa51d71be3f93477d136741bee2549f590c31';

/// Every unarchived chat on [hostId], kept current by the same tracker the
/// desktop uses, so workspace rows can list chats beside terminal agents.
/// Empty against a runtime without agent chats.

final class MobileChatAttentionEntriesFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileChatAttentionEntries,
          Map<String, ChatAttentionEntry>,
          Map<String, ChatAttentionEntry>,
          Map<String, ChatAttentionEntry>,
          String
        > {
  MobileChatAttentionEntriesFamily._()
    : super(
        retry: null,
        name: r'mobileChatAttentionEntriesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every unarchived chat on [hostId], kept current by the same tracker the
  /// desktop uses, so workspace rows can list chats beside terminal agents.
  /// Empty against a runtime without agent chats.

  MobileChatAttentionEntriesProvider call(String hostId) =>
      MobileChatAttentionEntriesProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileChatAttentionEntriesProvider';
}

/// Every unarchived chat on [hostId], kept current by the same tracker the
/// desktop uses, so workspace rows can list chats beside terminal agents.
/// Empty against a runtime without agent chats.

abstract class _$MobileChatAttentionEntries
    extends $Notifier<Map<String, ChatAttentionEntry>> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  Map<String, ChatAttentionEntry> build(String hostId);
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
    return element.handleCreate(ref, () => build(_$args));
  }
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_relationships.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The provider-native sub-agent a chat tab shows in place of the chat, by
/// the call that started it; `null` shows the chat itself.

@ProviderFor(AgentChatOpenSubagent)
final agentChatOpenSubagentProvider = AgentChatOpenSubagentFamily._();

/// The provider-native sub-agent a chat tab shows in place of the chat, by
/// the call that started it; `null` shows the chat itself.
final class AgentChatOpenSubagentProvider
    extends $NotifierProvider<AgentChatOpenSubagent, String?> {
  /// The provider-native sub-agent a chat tab shows in place of the chat, by
  /// the call that started it; `null` shows the chat itself.
  AgentChatOpenSubagentProvider._({
    required AgentChatOpenSubagentFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentChatOpenSubagentProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatOpenSubagentHash();

  @override
  String toString() {
    return r'agentChatOpenSubagentProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentChatOpenSubagent create() => AgentChatOpenSubagent();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatOpenSubagentProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatOpenSubagentHash() =>
    r'4cf42bea26580ef70c5da2c255ee48dcd83b2056';

/// The provider-native sub-agent a chat tab shows in place of the chat, by
/// the call that started it; `null` shows the chat itself.

final class AgentChatOpenSubagentFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentChatOpenSubagent,
          String?,
          String?,
          String?,
          String
        > {
  AgentChatOpenSubagentFamily._()
    : super(
        retry: null,
        name: r'agentChatOpenSubagentProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The provider-native sub-agent a chat tab shows in place of the chat, by
  /// the call that started it; `null` shows the chat itself.

  AgentChatOpenSubagentProvider call(String chatId) =>
      AgentChatOpenSubagentProvider._(argument: chatId, from: this);

  @override
  String toString() => r'agentChatOpenSubagentProvider';
}

/// The provider-native sub-agent a chat tab shows in place of the chat, by
/// the call that started it; `null` shows the chat itself.

abstract class _$AgentChatOpenSubagent extends $Notifier<String?> {
  late final _$args = ref.$arg as String;
  String get chatId => _$args;

  String? build(String chatId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// A sub-agent's transcript as the runtime stores it, so work on pages the
/// chat has not loaded still shows. Live items come from the chat itself.

@ProviderFor(agentChatSubagentTranscript)
final agentChatSubagentTranscriptProvider =
    AgentChatSubagentTranscriptFamily._();

/// A sub-agent's transcript as the runtime stores it, so work on pages the
/// chat has not loaded still shows. Live items come from the chat itself.

final class AgentChatSubagentTranscriptProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatSubagentTranscript>,
          AgentChatSubagentTranscript,
          FutureOr<AgentChatSubagentTranscript>
        >
    with
        $FutureModifier<AgentChatSubagentTranscript>,
        $FutureProvider<AgentChatSubagentTranscript> {
  /// A sub-agent's transcript as the runtime stores it, so work on pages the
  /// chat has not loaded still shows. Live items come from the chat itself.
  AgentChatSubagentTranscriptProvider._({
    required AgentChatSubagentTranscriptFamily super.from,
    required (String, String, String) super.argument,
  }) : super(
         retry: null,
         name: r'agentChatSubagentTranscriptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatSubagentTranscriptHash();

  @override
  String toString() {
    return r'agentChatSubagentTranscriptProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatSubagentTranscript> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatSubagentTranscript> create(Ref ref) {
    final argument = this.argument as (String, String, String);
    return agentChatSubagentTranscript(
      ref,
      argument.$1,
      argument.$2,
      argument.$3,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatSubagentTranscriptProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatSubagentTranscriptHash() =>
    r'a6b77c4921b944dc1119d6e7e123e0ab92806b77';

/// A sub-agent's transcript as the runtime stores it, so work on pages the
/// chat has not loaded still shows. Live items come from the chat itself.

final class AgentChatSubagentTranscriptFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatSubagentTranscript>,
          (String, String, String)
        > {
  AgentChatSubagentTranscriptFamily._()
    : super(
        retry: null,
        name: r'agentChatSubagentTranscriptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A sub-agent's transcript as the runtime stores it, so work on pages the
  /// chat has not loaded still shows. Live items come from the chat itself.

  AgentChatSubagentTranscriptProvider call(
    String chatId,
    String workspaceId,
    String callId,
  ) => AgentChatSubagentTranscriptProvider._(
    argument: (chatId, workspaceId, callId),
    from: this,
  );

  @override
  String toString() => r'agentChatSubagentTranscriptProvider';
}

/// Every chat the runtime knows, archived ones included, for the
/// relationships control: a parent or fork may live in another workspace.

@ProviderFor(agentChatRelatedChats)
final agentChatRelatedChatsProvider = AgentChatRelatedChatsProvider._();

/// Every chat the runtime knows, archived ones included, for the
/// relationships control: a parent or fork may live in another workspace.

final class AgentChatRelatedChatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentChatSummary>>,
          List<AgentChatSummary>,
          FutureOr<List<AgentChatSummary>>
        >
    with
        $FutureModifier<List<AgentChatSummary>>,
        $FutureProvider<List<AgentChatSummary>> {
  /// Every chat the runtime knows, archived ones included, for the
  /// relationships control: a parent or fork may live in another workspace.
  AgentChatRelatedChatsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatRelatedChatsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatRelatedChatsHash();

  @$internal
  @override
  $FutureProviderElement<List<AgentChatSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AgentChatSummary>> create(Ref ref) {
    return agentChatRelatedChats(ref);
  }
}

String _$agentChatRelatedChatsHash() =>
    r'a7cc949f4a93b2a783b2f2ce4e916ac000da813d';

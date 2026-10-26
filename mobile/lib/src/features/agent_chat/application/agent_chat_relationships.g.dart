// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_relationships.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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
    required (String, String, String, String) super.argument,
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
    final argument = this.argument as (String, String, String, String);
    return agentChatSubagentTranscript(
      ref,
      argument.$1,
      argument.$2,
      argument.$3,
      argument.$4,
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
    r'0142a1088d85e4702a599870ea953fbcd5869ff6';

/// A sub-agent's transcript as the runtime stores it, so work on pages the
/// chat has not loaded still shows. Live items come from the chat itself.

final class AgentChatSubagentTranscriptFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatSubagentTranscript>,
          (String, String, String, String)
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
    String hostId,
    String workspaceId,
    String chatId,
    String callId,
  ) => AgentChatSubagentTranscriptProvider._(
    argument: (hostId, workspaceId, chatId, callId),
    from: this,
  );

  @override
  String toString() => r'agentChatSubagentTranscriptProvider';
}

/// Every chat the paired runtime knows, archived ones included, for the
/// lineage sheet: a parent or fork may live in another workspace.

@ProviderFor(agentChatRelatedChats)
final agentChatRelatedChatsProvider = AgentChatRelatedChatsFamily._();

/// Every chat the paired runtime knows, archived ones included, for the
/// lineage sheet: a parent or fork may live in another workspace.

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
  /// Every chat the paired runtime knows, archived ones included, for the
  /// lineage sheet: a parent or fork may live in another workspace.
  AgentChatRelatedChatsProvider._({
    required AgentChatRelatedChatsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentChatRelatedChatsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatRelatedChatsHash();

  @override
  String toString() {
    return r'agentChatRelatedChatsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<AgentChatSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AgentChatSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return agentChatRelatedChats(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatRelatedChatsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatRelatedChatsHash() =>
    r'24cb8855443867eabe85c3ad184fb30418f76913';

/// Every chat the paired runtime knows, archived ones included, for the
/// lineage sheet: a parent or fork may live in another workspace.

final class AgentChatRelatedChatsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<AgentChatSummary>>, String> {
  AgentChatRelatedChatsFamily._()
    : super(
        retry: null,
        name: r'agentChatRelatedChatsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every chat the paired runtime knows, archived ones included, for the
  /// lineage sheet: a parent or fork may live in another workspace.

  AgentChatRelatedChatsProvider call(String hostId) =>
      AgentChatRelatedChatsProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentChatRelatedChatsProvider';
}

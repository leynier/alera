// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_workflows.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The script the workflow a call started runs (`agentChatWorkflowsV1`).

@ProviderFor(agentChatWorkflowScript)
final agentChatWorkflowScriptProvider = AgentChatWorkflowScriptFamily._();

/// The script the workflow a call started runs (`agentChatWorkflowsV1`).

final class AgentChatWorkflowScriptProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatWorkflowScript>,
          AgentChatWorkflowScript,
          FutureOr<AgentChatWorkflowScript>
        >
    with
        $FutureModifier<AgentChatWorkflowScript>,
        $FutureProvider<AgentChatWorkflowScript> {
  /// The script the workflow a call started runs (`agentChatWorkflowsV1`).
  AgentChatWorkflowScriptProvider._({
    required AgentChatWorkflowScriptFamily super.from,
    required (String, String, String, String) super.argument,
  }) : super(
         retry: null,
         name: r'agentChatWorkflowScriptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatWorkflowScriptHash();

  @override
  String toString() {
    return r'agentChatWorkflowScriptProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatWorkflowScript> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatWorkflowScript> create(Ref ref) {
    final argument = this.argument as (String, String, String, String);
    return agentChatWorkflowScript(
      ref,
      argument.$1,
      argument.$2,
      argument.$3,
      argument.$4,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatWorkflowScriptProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatWorkflowScriptHash() =>
    r'9d78a5cebfe7778c3e4816369cfb382c626f33a5';

/// The script the workflow a call started runs (`agentChatWorkflowsV1`).

final class AgentChatWorkflowScriptFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatWorkflowScript>,
          (String, String, String, String)
        > {
  AgentChatWorkflowScriptFamily._()
    : super(
        retry: null,
        name: r'agentChatWorkflowScriptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The script the workflow a call started runs (`agentChatWorkflowsV1`).

  AgentChatWorkflowScriptProvider call(
    String hostId,
    String workspaceId,
    String chatId,
    String callId,
  ) => AgentChatWorkflowScriptProvider._(
    argument: (hostId, workspaceId, chatId, callId),
    from: this,
  );

  @override
  String toString() => r'agentChatWorkflowScriptProvider';
}

/// What one member of that workflow answered, from its transcript.

@ProviderFor(agentChatWorkflowAnswers)
final agentChatWorkflowAnswersProvider = AgentChatWorkflowAnswersFamily._();

/// What one member of that workflow answered, from its transcript.

final class AgentChatWorkflowAnswersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          FutureOr<List<String>>
        >
    with $FutureModifier<List<String>>, $FutureProvider<List<String>> {
  /// What one member of that workflow answered, from its transcript.
  AgentChatWorkflowAnswersProvider._({
    required AgentChatWorkflowAnswersFamily super.from,
    required (String, String, String, String, int) super.argument,
  }) : super(
         retry: null,
         name: r'agentChatWorkflowAnswersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatWorkflowAnswersHash();

  @override
  String toString() {
    return r'agentChatWorkflowAnswersProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<String>> create(Ref ref) {
    final argument = this.argument as (String, String, String, String, int);
    return agentChatWorkflowAnswers(
      ref,
      argument.$1,
      argument.$2,
      argument.$3,
      argument.$4,
      argument.$5,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatWorkflowAnswersProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatWorkflowAnswersHash() =>
    r'aa27a7f195adcede38c543f0f2061f0a72fd87d4';

/// What one member of that workflow answered, from its transcript.

final class AgentChatWorkflowAnswersFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<String>>,
          (String, String, String, String, int)
        > {
  AgentChatWorkflowAnswersFamily._()
    : super(
        retry: null,
        name: r'agentChatWorkflowAnswersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// What one member of that workflow answered, from its transcript.

  AgentChatWorkflowAnswersProvider call(
    String hostId,
    String workspaceId,
    String chatId,
    String callId,
    int agentIndex,
  ) => AgentChatWorkflowAnswersProvider._(
    argument: (hostId, workspaceId, chatId, callId, agentIndex),
    from: this,
  );

  @override
  String toString() => r'agentChatWorkflowAnswersProvider';
}

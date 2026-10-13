// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One chat on the paired runtime and what the person asks of it. The runtime
/// owns the transcript and the provider process; this mirrors one and
/// forwards the other. Every mutation carries a request id the runtime
/// deduplicates, so a retry after a dropped connection never acts twice.
///
/// The notifier outlives rebuilds, so prompts still on their way survive a
/// reconnect, while the thread is always reloaded from a fresh snapshot.

@ProviderFor(AgentChatController)
final agentChatControllerProvider = AgentChatControllerFamily._();

/// One chat on the paired runtime and what the person asks of it. The runtime
/// owns the transcript and the provider process; this mirrors one and
/// forwards the other. Every mutation carries a request id the runtime
/// deduplicates, so a retry after a dropped connection never acts twice.
///
/// The notifier outlives rebuilds, so prompts still on their way survive a
/// reconnect, while the thread is always reloaded from a fresh snapshot.
final class AgentChatControllerProvider
    extends $AsyncNotifierProvider<AgentChatController, AgentChatViewState> {
  /// One chat on the paired runtime and what the person asks of it. The runtime
  /// owns the transcript and the provider process; this mirrors one and
  /// forwards the other. Every mutation carries a request id the runtime
  /// deduplicates, so a retry after a dropped connection never acts twice.
  ///
  /// The notifier outlives rebuilds, so prompts still on their way survive a
  /// reconnect, while the thread is always reloaded from a fresh snapshot.
  AgentChatControllerProvider._({
    required AgentChatControllerFamily super.from,
    required (String, String, String) super.argument,
  }) : super(
         retry: null,
         name: r'agentChatControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatControllerHash();

  @override
  String toString() {
    return r'agentChatControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  AgentChatController create() => AgentChatController();

  @override
  bool operator ==(Object other) {
    return other is AgentChatControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatControllerHash() =>
    r'09429f7af74b0e82136e35b0b811711ca402e5dc';

/// One chat on the paired runtime and what the person asks of it. The runtime
/// owns the transcript and the provider process; this mirrors one and
/// forwards the other. Every mutation carries a request id the runtime
/// deduplicates, so a retry after a dropped connection never acts twice.
///
/// The notifier outlives rebuilds, so prompts still on their way survive a
/// reconnect, while the thread is always reloaded from a fresh snapshot.

final class AgentChatControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentChatController,
          AsyncValue<AgentChatViewState>,
          AgentChatViewState,
          FutureOr<AgentChatViewState>,
          (String, String, String)
        > {
  AgentChatControllerFamily._()
    : super(
        retry: null,
        name: r'agentChatControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One chat on the paired runtime and what the person asks of it. The runtime
  /// owns the transcript and the provider process; this mirrors one and
  /// forwards the other. Every mutation carries a request id the runtime
  /// deduplicates, so a retry after a dropped connection never acts twice.
  ///
  /// The notifier outlives rebuilds, so prompts still on their way survive a
  /// reconnect, while the thread is always reloaded from a fresh snapshot.

  AgentChatControllerProvider call(
    String hostId,
    String workspaceId,
    String chatId,
  ) => AgentChatControllerProvider._(
    argument: (hostId, workspaceId, chatId),
    from: this,
  );

  @override
  String toString() => r'agentChatControllerProvider';
}

/// One chat on the paired runtime and what the person asks of it. The runtime
/// owns the transcript and the provider process; this mirrors one and
/// forwards the other. Every mutation carries a request id the runtime
/// deduplicates, so a retry after a dropped connection never acts twice.
///
/// The notifier outlives rebuilds, so prompts still on their way survive a
/// reconnect, while the thread is always reloaded from a fresh snapshot.

abstract class _$AgentChatController
    extends $AsyncNotifier<AgentChatViewState> {
  late final _$args = ref.$arg as (String, String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;
  String get chatId => _$args.$3;

  FutureOr<AgentChatViewState> build(
    String hostId,
    String workspaceId,
    String chatId,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<AgentChatViewState>, AgentChatViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AgentChatViewState>, AgentChatViewState>,
              AsyncValue<AgentChatViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3),
    );
  }
}

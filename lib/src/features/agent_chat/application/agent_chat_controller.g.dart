// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One chat as the desktop renders it: a runtime snapshot kept current by
/// cursor-ordered changes, plus this client's in-flight actions.

@ProviderFor(AgentChatController)
final agentChatControllerProvider = AgentChatControllerFamily._();

/// One chat as the desktop renders it: a runtime snapshot kept current by
/// cursor-ordered changes, plus this client's in-flight actions.
final class AgentChatControllerProvider
    extends $NotifierProvider<AgentChatController, AgentChatViewState> {
  /// One chat as the desktop renders it: a runtime snapshot kept current by
  /// cursor-ordered changes, plus this client's in-flight actions.
  AgentChatControllerProvider._({
    required AgentChatControllerFamily super.from,
    required (String, String) super.argument,
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

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatViewState>(value),
    );
  }

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
    r'e62c6aade2c1c46703ded01af4ed9a6a1e21e3b9';

/// One chat as the desktop renders it: a runtime snapshot kept current by
/// cursor-ordered changes, plus this client's in-flight actions.

final class AgentChatControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentChatController,
          AgentChatViewState,
          AgentChatViewState,
          AgentChatViewState,
          (String, String)
        > {
  AgentChatControllerFamily._()
    : super(
        retry: null,
        name: r'agentChatControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One chat as the desktop renders it: a runtime snapshot kept current by
  /// cursor-ordered changes, plus this client's in-flight actions.

  AgentChatControllerProvider call(String chatId, String workspaceId) =>
      AgentChatControllerProvider._(
        argument: (chatId, workspaceId),
        from: this,
      );

  @override
  String toString() => r'agentChatControllerProvider';
}

/// One chat as the desktop renders it: a runtime snapshot kept current by
/// cursor-ordered changes, plus this client's in-flight actions.

abstract class _$AgentChatController extends $Notifier<AgentChatViewState> {
  late final _$args = ref.$arg as (String, String);
  String get chatId => _$args.$1;
  String get workspaceId => _$args.$2;

  AgentChatViewState build(String chatId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AgentChatViewState, AgentChatViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AgentChatViewState, AgentChatViewState>,
              AgentChatViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

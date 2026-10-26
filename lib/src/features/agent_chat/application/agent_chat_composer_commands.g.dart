// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_composer_commands.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Commands that keyboard actions and New Agent Chat send to the composer of
/// a chat that is already on screen. A chat that is not mounted ignores them.

@ProviderFor(AgentChatComposerCommands)
final agentChatComposerCommandsProvider = AgentChatComposerCommandsProvider._();

/// Commands that keyboard actions and New Agent Chat send to the composer of
/// a chat that is already on screen. A chat that is not mounted ignores them.
final class AgentChatComposerCommandsProvider
    extends
        $NotifierProvider<
          AgentChatComposerCommands,
          AgentChatComposerCommand?
        > {
  /// Commands that keyboard actions and New Agent Chat send to the composer of
  /// a chat that is already on screen. A chat that is not mounted ignores them.
  AgentChatComposerCommandsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatComposerCommandsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatComposerCommandsHash();

  @$internal
  @override
  AgentChatComposerCommands create() => AgentChatComposerCommands();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatComposerCommand? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatComposerCommand?>(value),
    );
  }
}

String _$agentChatComposerCommandsHash() =>
    r'1b9b16152c4d5faa6a08a535931db02333bae22a';

/// Commands that keyboard actions and New Agent Chat send to the composer of
/// a chat that is already on screen. A chat that is not mounted ignores them.

abstract class _$AgentChatComposerCommands
    extends $Notifier<AgentChatComposerCommand?> {
  AgentChatComposerCommand? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AgentChatComposerCommand?, AgentChatComposerCommand?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AgentChatComposerCommand?, AgentChatComposerCommand?>,
              AgentChatComposerCommand?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

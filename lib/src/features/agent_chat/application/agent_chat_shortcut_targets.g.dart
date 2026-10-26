// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_shortcut_targets.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentChatShortcutTargets)
final agentChatShortcutTargetsProvider = AgentChatShortcutTargetsProvider._();

final class AgentChatShortcutTargetsProvider
    extends
        $FunctionalProvider<
          AgentChatShortcutTargets,
          AgentChatShortcutTargets,
          AgentChatShortcutTargets
        >
    with $Provider<AgentChatShortcutTargets> {
  AgentChatShortcutTargetsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatShortcutTargetsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatShortcutTargetsHash();

  @$internal
  @override
  $ProviderElement<AgentChatShortcutTargets> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatShortcutTargets create(Ref ref) {
    return agentChatShortcutTargets(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatShortcutTargets value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatShortcutTargets>(value),
    );
  }
}

String _$agentChatShortcutTargetsHash() =>
    r'32828f5380fbfaaada4a1295c746c4dfa0840639';

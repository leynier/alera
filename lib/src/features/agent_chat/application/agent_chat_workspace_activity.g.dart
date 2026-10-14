// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_workspace_activity.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The activity of every chat in a workspace, so a chat tab that is not open
/// still shows that its agent is working or waits on the person. Seeded from
/// `agentChat.list` and kept current from each chat's session and request
/// changes; any list change or reconnect reads the list again.

@ProviderFor(AgentChatWorkspaceActivity)
final agentChatWorkspaceActivityProvider = AgentChatWorkspaceActivityFamily._();

/// The activity of every chat in a workspace, so a chat tab that is not open
/// still shows that its agent is working or waits on the person. Seeded from
/// `agentChat.list` and kept current from each chat's session and request
/// changes; any list change or reconnect reads the list again.
final class AgentChatWorkspaceActivityProvider
    extends
        $NotifierProvider<
          AgentChatWorkspaceActivity,
          Map<String, AgentChatTabActivity>
        > {
  /// The activity of every chat in a workspace, so a chat tab that is not open
  /// still shows that its agent is working or waits on the person. Seeded from
  /// `agentChat.list` and kept current from each chat's session and request
  /// changes; any list change or reconnect reads the list again.
  AgentChatWorkspaceActivityProvider._({
    required AgentChatWorkspaceActivityFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentChatWorkspaceActivityProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatWorkspaceActivityHash();

  @override
  String toString() {
    return r'agentChatWorkspaceActivityProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentChatWorkspaceActivity create() => AgentChatWorkspaceActivity();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AgentChatTabActivity> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AgentChatTabActivity>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatWorkspaceActivityProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatWorkspaceActivityHash() =>
    r'2c6c3f8b98d86f3d03ab7d796ddef93d6f1823bc';

/// The activity of every chat in a workspace, so a chat tab that is not open
/// still shows that its agent is working or waits on the person. Seeded from
/// `agentChat.list` and kept current from each chat's session and request
/// changes; any list change or reconnect reads the list again.

final class AgentChatWorkspaceActivityFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentChatWorkspaceActivity,
          Map<String, AgentChatTabActivity>,
          Map<String, AgentChatTabActivity>,
          Map<String, AgentChatTabActivity>,
          String
        > {
  AgentChatWorkspaceActivityFamily._()
    : super(
        retry: null,
        name: r'agentChatWorkspaceActivityProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The activity of every chat in a workspace, so a chat tab that is not open
  /// still shows that its agent is working or waits on the person. Seeded from
  /// `agentChat.list` and kept current from each chat's session and request
  /// changes; any list change or reconnect reads the list again.

  AgentChatWorkspaceActivityProvider call(String workspaceId) =>
      AgentChatWorkspaceActivityProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'agentChatWorkspaceActivityProvider';
}

/// The activity of every chat in a workspace, so a chat tab that is not open
/// still shows that its agent is working or waits on the person. Seeded from
/// `agentChat.list` and kept current from each chat's session and request
/// changes; any list change or reconnect reads the list again.

abstract class _$AgentChatWorkspaceActivity
    extends $Notifier<Map<String, AgentChatTabActivity>> {
  late final _$args = ref.$arg as String;
  String get workspaceId => _$args;

  Map<String, AgentChatTabActivity> build(String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, AgentChatTabActivity>,
              Map<String, AgentChatTabActivity>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, AgentChatTabActivity>,
                Map<String, AgentChatTabActivity>
              >,
              Map<String, AgentChatTabActivity>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

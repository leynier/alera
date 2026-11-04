// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_automation_agent_chats.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The open agent chats of [workspaceId] on [hostId] an automation can post
/// into, most recently updated first. A change to the chat list reads them
/// again.

@ProviderFor(mobileAutomationAgentChats)
final mobileAutomationAgentChatsProvider = MobileAutomationAgentChatsFamily._();

/// The open agent chats of [workspaceId] on [hostId] an automation can post
/// into, most recently updated first. A change to the chat list reads them
/// again.

final class MobileAutomationAgentChatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentChatSummary>>,
          List<AgentChatSummary>,
          FutureOr<List<AgentChatSummary>>
        >
    with
        $FutureModifier<List<AgentChatSummary>>,
        $FutureProvider<List<AgentChatSummary>> {
  /// The open agent chats of [workspaceId] on [hostId] an automation can post
  /// into, most recently updated first. A change to the chat list reads them
  /// again.
  MobileAutomationAgentChatsProvider._({
    required MobileAutomationAgentChatsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationAgentChatsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationAgentChatsHash();

  @override
  String toString() {
    return r'mobileAutomationAgentChatsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<AgentChatSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AgentChatSummary>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return mobileAutomationAgentChats(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationAgentChatsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationAgentChatsHash() =>
    r'616a668d2d57fc6c73006b6278b76c3ecd1e4356';

/// The open agent chats of [workspaceId] on [hostId] an automation can post
/// into, most recently updated first. A change to the chat list reads them
/// again.

final class MobileAutomationAgentChatsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<AgentChatSummary>>,
          (String, String)
        > {
  MobileAutomationAgentChatsFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationAgentChatsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The open agent chats of [workspaceId] on [hostId] an automation can post
  /// into, most recently updated first. A change to the chat list reads them
  /// again.

  MobileAutomationAgentChatsProvider call(String hostId, String workspaceId) =>
      MobileAutomationAgentChatsProvider._(
        argument: (hostId, workspaceId),
        from: this,
      );

  @override
  String toString() => r'mobileAutomationAgentChatsProvider';
}

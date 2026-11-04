// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_agent_chats.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The open agent chats of [workspaceId] an automation can post into, most
/// recently updated first. A change to the chat list reads them again.

@ProviderFor(automationAgentChats)
final automationAgentChatsProvider = AutomationAgentChatsFamily._();

/// The open agent chats of [workspaceId] an automation can post into, most
/// recently updated first. A change to the chat list reads them again.

final class AutomationAgentChatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentChatSummary>>,
          List<AgentChatSummary>,
          FutureOr<List<AgentChatSummary>>
        >
    with
        $FutureModifier<List<AgentChatSummary>>,
        $FutureProvider<List<AgentChatSummary>> {
  /// The open agent chats of [workspaceId] an automation can post into, most
  /// recently updated first. A change to the chat list reads them again.
  AutomationAgentChatsProvider._({
    required AutomationAgentChatsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'automationAgentChatsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$automationAgentChatsHash();

  @override
  String toString() {
    return r'automationAgentChatsProvider'
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
    return automationAgentChats(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AutomationAgentChatsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$automationAgentChatsHash() =>
    r'6a4f0284e323b0a18a8c701202a055a2242bdee3';

/// The open agent chats of [workspaceId] an automation can post into, most
/// recently updated first. A change to the chat list reads them again.

final class AutomationAgentChatsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<AgentChatSummary>>, String> {
  AutomationAgentChatsFamily._()
    : super(
        retry: null,
        name: r'automationAgentChatsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The open agent chats of [workspaceId] an automation can post into, most
  /// recently updated first. A change to the chat list reads them again.

  AutomationAgentChatsProvider call(String workspaceId) =>
      AutomationAgentChatsProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'automationAgentChatsProvider';
}

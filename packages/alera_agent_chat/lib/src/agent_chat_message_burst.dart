import 'package:alera_agent_chat/src/agent_chat_item.dart';

/// Where a message the person steered into a running turn sits in its burst:
/// back-to-back steers stack tight with joined corners and share one label,
/// on the last of them. Input an agent or the runtime sent breaks a burst.
final class const AgentChatSteerPlacement({
  final bool joinsPrevious = false,
  final bool joinsNext = false,
}) {
  /// A steer alone in its burst.
  static const AgentChatSteerPlacement single = AgentChatSteerPlacement();

  /// Whether this steer carries the burst's label.
  bool get labeled => !joinsNext;
}

/// The placement of each of [steers], in order: steers within one segment
/// arrive back to back, with no agent output between them.
List<AgentChatSteerPlacement> agentChatSteerPlacements(
  List<AgentChatItem> steers,
) {
  bool own(int index) =>
      index >= 0 && index < steers.length && !steers[index].isAutomatedInput;
  return <AgentChatSteerPlacement>[
    for (var index = 0; index < steers.length; index += 1)
      own(index)
          ? AgentChatSteerPlacement(
              joinsPrevious: own(index - 1),
              joinsNext: own(index + 1),
            )
          : AgentChatSteerPlacement.single,
  ];
}

import 'package:flutter/widgets.dart';

/// What a chat tab lets its sub-agent rows do: open a sub-agent in place of
/// the chat and, where the runtime and provider allow it, stop one.
class AgentChatSubagentScope extends InheritedWidget {
  const AgentChatSubagentScope({
    super.key,
    required this.onOpen,
    required this.onStop,
    required this.stopping,
    required super.child,
  });

  /// Opens the sub-agent the call started; `null` without
  /// `agentChatSubagentThreadsV1`.
  final ValueChanged<String>? onOpen;

  /// Stops the running sub-agent the call started; `null` when the runtime
  /// or the chat's provider cannot.
  final ValueChanged<String>? onStop;

  /// Calls whose stop is in flight.
  final Set<String> stopping;

  static AgentChatSubagentScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgentChatSubagentScope>();

  @override
  bool updateShouldNotify(AgentChatSubagentScope oldWidget) =>
      onOpen != oldWidget.onOpen ||
      onStop != oldWidget.onStop ||
      stopping != oldWidget.stopping;
}

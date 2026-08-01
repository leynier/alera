import 'package:alera/src/features/agent_status/domain/agent_status.dart';

/// How the host hands a dispatched task prompt to a freshly launched agent.
///
/// The source of truth is `startup_delivery` in
/// `rust/alera-cli/src/terminal_host/orchestration/agent_registry.rs`. It
/// decides whether a launch command receives the prompt as an argument or the
/// prompt is typed into the running TUI, which is the one thing a user writing
/// a Command-mode profile has to know.
enum AgentPromptDelivery {
  /// The prompt is appended to the command after the option terminator.
  initialPromptArgument,

  /// The command launches bare and the prompt is typed in once the agent
  /// reports that it is ready.
  readinessInjection,
}

/// Mirrors the option terminator the host inserts before an argument prompt.
const String agentPromptOptionTerminator = '--';

AgentPromptDelivery agentPromptDeliveryFor(AgentType adapter) {
  return adapter == AgentType.codex
      ? AgentPromptDelivery.initialPromptArgument
      : AgentPromptDelivery.readinessInjection;
}

/// How the prompt reaches the agent, in the user's terms.
String agentPromptDeliveryDescription(AgentType adapter) {
  return switch (agentPromptDeliveryFor(adapter)) {
    AgentPromptDelivery.initialPromptArgument =>
      'Alera Appends The Dispatched Prompt To This Command As One Quoted '
          'Argument, After $agentPromptOptionTerminator So A Prompt Starting '
          'With A Dash Is Not Read As An Option. Write Only The Flags Here.',
    AgentPromptDelivery.readinessInjection =>
      'This Command Launches Without A Prompt. Alera Types The Dispatched '
          'Prompt Into The Agent Once It Reports That It Is Ready. Write Only '
          'The Flags Here.',
  };
}

/// The shape of the launch line with the prompt in place, or empty when the
/// prompt never reaches the command line at all.
String agentPromptDeliveryPreview(AgentType adapter, String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty ||
      agentPromptDeliveryFor(adapter) !=
          AgentPromptDelivery.initialPromptArgument) {
    return '';
  }
  return "$trimmed $agentPromptOptionTerminator 'Dispatched Prompt'";
}

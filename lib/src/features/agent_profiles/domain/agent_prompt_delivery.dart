import 'package:alera/src/features/agent_status/domain/agent_status.dart';

/// How the host hands a dispatched task prompt to a freshly launched agent.
///
/// The source of truth is `startup_prompt` in
/// `rust/alera-cli/src/terminal_host/orchestration/agent_registry.rs`. Every
/// agent receives its prompt at launch; what differs is the shape its own CLI
/// accepts, which is the one thing a user writing a Command-mode profile has to
/// know, since Alera appends to whatever they wrote.
enum AgentPromptDelivery {
  /// Appended as a positional argument after the option terminator.
  positionalAfterTerminator,

  /// Appended as a bare positional argument, with no terminator available.
  positional,

  /// Appended as a single `--flag=<prompt>` token.
  longOption,

  /// Never reaches the command line: the agent reads it from stdin.
  stdinScript,
}

/// Mirrors the option terminator the host inserts before an argument prompt.
const String agentPromptOptionTerminator = '--';

/// The long option each flag-carrying agent takes its initial prompt in.
const Map<AgentType, String> agentPromptDeliveryOptions = <AgentType, String>{
  AgentType.copilot: '--interactive',
  AgentType.agy: '--prompt-interactive',
  AgentType.opencode: '--prompt',
};

AgentPromptDelivery agentPromptDeliveryFor(AgentType adapter) {
  if (agentPromptDeliveryOptions.containsKey(adapter)) {
    return AgentPromptDelivery.longOption;
  }
  return switch (adapter) {
    AgentType.amp => AgentPromptDelivery.stdinScript,
    // pi rejects the option terminator outright, so its prompt goes in bare.
    AgentType.pi => AgentPromptDelivery.positional,
    _ => AgentPromptDelivery.positionalAfterTerminator,
  };
}

/// How the prompt reaches the agent, in the user's terms.
String agentPromptDeliveryDescription(AgentType adapter) {
  return switch (agentPromptDeliveryFor(adapter)) {
    AgentPromptDelivery.positionalAfterTerminator =>
      'Alera appends the dispatched prompt to this command as one quoted '
          'argument after $agentPromptOptionTerminator, so a prompt starting '
          'with a dash is not read as an option. Write only the flags here.',
    AgentPromptDelivery.positional =>
      'Alera appends the dispatched prompt to this command as one quoted '
          'argument. This agent does not accept an option terminator, so a '
          'prompt starting with a dash gets a leading space to keep it out of '
          'the parser. Write only the flags here.',
    AgentPromptDelivery.longOption =>
      'Alera appends the dispatched prompt to this command as a single quoted '
          '${agentPromptDeliveryOptions[adapter]} argument. Write only the '
          'other flags here.',
    AgentPromptDelivery.stdinScript =>
      'This agent has no option for an initial prompt, so Alera runs the '
          'command through a generated script that feeds the dispatched prompt '
          'on standard input. Write only the flags here.',
  };
}

/// The shape of the launch line with the prompt in place, or empty when the
/// prompt never reaches the command line at all.
String agentPromptDeliveryPreview(AgentType adapter, String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  const String prompt = 'Dispatched Prompt';
  return switch (agentPromptDeliveryFor(adapter)) {
    AgentPromptDelivery.positionalAfterTerminator =>
      "$trimmed $agentPromptOptionTerminator '$prompt'",
    AgentPromptDelivery.positional => "$trimmed '$prompt'",
    AgentPromptDelivery.longOption =>
      "$trimmed '${agentPromptDeliveryOptions[adapter]}=$prompt'",
    AgentPromptDelivery.stdinScript => '',
  };
}

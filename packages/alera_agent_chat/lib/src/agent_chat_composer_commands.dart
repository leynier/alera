import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_command.dart';

/// A local `/` command of the chat composer: it changes the composer or
/// opens one of its controls instead of being sent to the agent. Desktop and
/// phone share the table so a command reads and behaves the same on both.
enum AgentChatSlashCommand(this.name, this.title, this.description) {
  model('model', 'Choose Model', 'Open the agent and model picker.'),
  plan('plan', 'Plan Mode', 'Plan before acting, from the next message.'),
  standard(
    'default',
    'Default Mode',
    'Leave plan mode and act on the next message.',
  ),
  usage('usage', 'Show Usage', 'Show the context window and usage limits.');

  /// What follows the slash, such as `model`.
  final String name;

  final String title;

  final String description;

  /// The command as typed, such as `/model`.
  String get label => '/$name';
}

/// What decides which commands apply to the chat right now.
final class const AgentChatSlashCommandState({
  final bool modelPickerAvailable = true,
  final String? modelPickerBlockedReason,
  final bool planModeSupported = false,
  final AgentChatInteractionMode interactionMode =
      AgentChatInteractionMode.standard,
  final bool configuring = false,
  final bool usageAvailable = false,

  /// What the agent advertises, listed after the local commands.
  final List<AgentChatProviderCommand> providerCommands =
      const <AgentChatProviderCommand>[],
});

/// A command the composer menu lists, with why it cannot run when it is
/// listed but disabled.
final class const AgentChatSlashCommandOption({
  required final AgentChatSlashCommand command,
  final String? disabledReason,
}) {
  bool get enabled => disabledReason == null;

  @override
  bool operator ==(Object other) =>
      other is AgentChatSlashCommandOption &&
      other.command == command &&
      other.disabledReason == disabledReason;

  @override
  int get hashCode => Object.hash(command, disabledReason);
}

const String agentChatSlashCommandConfiguringReason =
    'The chat settings are being applied.';
const String agentChatSlashCommandModelPickerUnavailableReason =
    'The model picker is not available right now.';
const String agentChatSlashCommandPlanActiveReason = 'Plan mode is already on.';
const String agentChatSlashCommandDefaultActiveReason =
    'Default mode is already on.';
const String agentChatSlashCommandUsageUnavailableReason =
    'The agent has not reported usage yet.';

/// The commands for [state] whose name matches [query], the text typed after
/// the slash. Plan and default mode are hidden when the agent has no plan
/// mode; every other command that cannot run stays listed with the reason.
/// Names that start with [query] come before names that only contain it.
List<AgentChatSlashCommandOption> agentChatSlashCommandOptions(
  AgentChatSlashCommandState state, {
  String query = '',
}) {
  final options = <AgentChatSlashCommandOption>[
    AgentChatSlashCommandOption(
      command: AgentChatSlashCommand.model,
      disabledReason: state.modelPickerAvailable
          ? null
          : state.modelPickerBlockedReason ??
                agentChatSlashCommandModelPickerUnavailableReason,
    ),
    if (state.planModeSupported) ...<AgentChatSlashCommandOption>[
      AgentChatSlashCommandOption(
        command: AgentChatSlashCommand.plan,
        disabledReason: state.configuring
            ? agentChatSlashCommandConfiguringReason
            : state.interactionMode == AgentChatInteractionMode.plan
            ? agentChatSlashCommandPlanActiveReason
            : null,
      ),
      AgentChatSlashCommandOption(
        command: AgentChatSlashCommand.standard,
        disabledReason: state.configuring
            ? agentChatSlashCommandConfiguringReason
            : state.interactionMode == AgentChatInteractionMode.standard
            ? agentChatSlashCommandDefaultActiveReason
            : null,
      ),
    ],
    AgentChatSlashCommandOption(
      command: AgentChatSlashCommand.usage,
      disabledReason: state.usageAvailable
          ? null
          : agentChatSlashCommandUsageUnavailableReason,
    ),
  ];
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return options;
  return <AgentChatSlashCommandOption>[
    for (final option in options)
      if (option.command.name.startsWith(needle)) option,
    for (final option in options)
      if (!option.command.name.startsWith(needle) &&
          option.command.name.contains(needle))
        option,
  ];
}

/// The interaction mode a mode command switches to, or `null` for a command
/// that does not change the mode.
AgentChatInteractionMode? agentChatSlashCommandInteractionMode(
  AgentChatSlashCommand command,
) => switch (command) {
  AgentChatSlashCommand.plan => AgentChatInteractionMode.plan,
  AgentChatSlashCommand.standard => AgentChatInteractionMode.standard,
  AgentChatSlashCommand.model || AgentChatSlashCommand.usage => null,
};

/// A row of the `/` menu: a local command, or one the agent advertises.
sealed class AgentChatSlashMenuEntry {
  const AgentChatSlashMenuEntry();

  /// What follows the slash.
  String get name;
}

final class const AgentChatSlashMenuLocalCommand(
  final AgentChatSlashCommandOption option,
) extends AgentChatSlashMenuEntry {
  @override
  String get name => option.command.name;

  @override
  bool operator ==(Object other) =>
      other is AgentChatSlashMenuLocalCommand && other.option == option;

  @override
  int get hashCode => option.hashCode;
}

final class const AgentChatSlashMenuProviderCommand(
  final AgentChatProviderCommand command,
) extends AgentChatSlashMenuEntry {
  @override
  String get name => command.name;

  @override
  bool operator ==(Object other) =>
      other is AgentChatSlashMenuProviderCommand && other.command == command;

  @override
  int get hashCode => command.hashCode;
}

/// Names the local table owns. They stay the composer's even while one of
/// them is hidden, so typing `/plan` never means one thing in one chat and
/// another in the next.
final Set<String> _localCommandNames = <String>{
  for (final command in AgentChatSlashCommand.values) command.name,
};

/// The `/` menu for [state] whose names match [query]: the local commands
/// of [agentChatSlashCommandOptions], then the agent's own. A local command
/// wins over an agent command of the same name, compared without case.
/// Names that start with [query] come before names that only contain it.
List<AgentChatSlashMenuEntry> agentChatSlashMenuEntries(
  AgentChatSlashCommandState state, {
  String query = '',
}) {
  final seen = <String>{..._localCommandNames};
  final entries = <AgentChatSlashMenuEntry>[
    for (final option in agentChatSlashCommandOptions(state))
      AgentChatSlashMenuLocalCommand(option),
    for (final command in state.providerCommands)
      if (seen.add(command.name.toLowerCase()))
        AgentChatSlashMenuProviderCommand(command),
  ];
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return entries;
  return <AgentChatSlashMenuEntry>[
    for (final entry in entries)
      if (entry.name.toLowerCase().startsWith(needle)) entry,
    for (final entry in entries)
      if (!entry.name.toLowerCase().startsWith(needle) &&
          entry.name.toLowerCase().contains(needle))
        entry,
  ];
}

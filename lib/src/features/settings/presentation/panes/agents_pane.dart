import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_all_skills_control.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_computer_use_skill_control.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_emulator_skill_control.dart';
import 'package:alera/src/features/settings/presentation/panes/agents_cli_skill_control.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_orchestration_skill_control.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Agent integration preferences: the Alera CLI skill, per-agent status
/// hooks, and agent-driven behavior toggles.
class AgentsSettingsPane extends ConsumerWidget {
  const AgentsSettingsPane({
    super.key,
    required this.agents,
    this.groupKeys = const <String, GlobalKey>{},
  });

  final AgentSettings agents;
  final Map<String, GlobalKey> groupKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeyedSubtree(
          key: groupKeys['cliSkill'],
          child: const AleraSettingsGroup(
            title: 'Alera CLI And Skills',
            description:
                'Register the CLI command and install agent instructions.',
            children: <Widget>[
              AleraSettingRow(
                title: 'Alera CLI Command',
                description:
                    'Register the Alera command on PATH for terminals and agents.',
                controlWidth: 360,
                child: AleraCliRegistrationControl(),
              ),
              AleraSettingRow(
                title: 'All Alera Skills',
                description:
                    'Install or update CLI, orchestration, computer use, and emulator skills. Reapplies selected status hooks.',
                controlWidth: 360,
                child: AleraAllSkillsControl(),
              ),
              AleraSettingRow(
                title: 'Alera CLI Skill',
                description:
                    'Install the Codex skill that teaches agents to use the Alera CLI.',
                controlWidth: 360,
                child: AleraCliSkillControl(),
              ),
              AleraSettingRow(
                title: 'Alera Orchestration Skill',
                description:
                    'Install or update orchestration and reapply selected status hooks.',
                controlWidth: 360,
                child: AleraOrchestrationSkillControl(),
              ),
              AleraSettingRow(
                title: 'Alera Computer Use Skill',
                description:
                    'Install the skill for reading and operating desktop applications.',
                controlWidth: 360,
                child: AleraComputerUseSkillControl(),
              ),
              AleraSettingRow(
                title: 'Alera Emulator Skill',
                description:
                    'Install the skill for Android and iOS emulator automation.',
                controlWidth: 360,
                child: AleraEmulatorSkillControl(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: groupKeys['hooks'],
          child: AleraSettingsGroup(
            title: 'Status Hooks',
            description: 'Managed hooks let terminal tabs show agent state.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Codex Hooks',
                description:
                    'Use an Alera-managed Codex runtime home with status hooks.',
                value: agents.agentStatusHooks.codex,
                onChanged: (value) => controller.setAgentStatusHookEnabled(
                  AgentType.codex,
                  value,
                ),
              ),
              SettingsSwitchRow(
                title: 'Claude Code Hooks',
                description:
                    'Use an Alera-managed Claude Code config with status hooks.',
                value: agents.agentStatusHooks.claude,
                onChanged: (value) => controller.setAgentStatusHookEnabled(
                  AgentType.claude,
                  value,
                ),
              ),
              SettingsSwitchRow(
                title: 'GitHub Copilot Hooks',
                description:
                    'Use an Alera-managed GitHub Copilot home overlay.',
                value: agents.agentStatusHooks.copilot,
                onChanged: (value) => controller.setAgentStatusHookEnabled(
                  AgentType.copilot,
                  value,
                ),
              ),
              SettingsSwitchRow(
                title: 'Cursor Hooks',
                description:
                    'Use an Alera-managed Cursor agent plugin wrapper.',
                value: agents.agentStatusHooks.cursor,
                onChanged: (value) => controller.setAgentStatusHookEnabled(
                  AgentType.cursor,
                  value,
                ),
              ),
              SettingsSwitchRow(
                title: 'Antigravity Hooks',
                description:
                    'Install Alera-managed Antigravity hooks for the agy CLI. Disable to remove only Alera-managed hook entries.',
                value: agents.agentStatusHooks.agy,
                onChanged: (value) =>
                    controller.setAgentStatusHookEnabled(AgentType.agy, value),
              ),
              SettingsSwitchRow(
                title: 'OpenCode Hooks',
                description:
                    'Use an Alera-managed OpenCode config overlay with status plugin.',
                value: agents.agentStatusHooks.opencode,
                onChanged: (value) => controller.setAgentStatusHookEnabled(
                  AgentType.opencode,
                  value,
                ),
              ),
              SettingsSwitchRow(
                title: 'Pi Hooks',
                description:
                    'Use an Alera-managed Pi agent overlay with status extension.',
                value: agents.agentStatusHooks.pi,
                onChanged: (value) =>
                    controller.setAgentStatusHookEnabled(AgentType.pi, value),
              ),
              SettingsSwitchRow(
                title: 'Amp Hooks',
                description: 'Use an Alera-managed Amp config overlay.',
                value: agents.agentStatusHooks.amp,
                onChanged: (value) =>
                    controller.setAgentStatusHookEnabled(AgentType.amp, value),
              ),
              SettingsSwitchRow(
                title: 'Grok Build Hooks',
                description:
                    'Install Alera-managed Grok build hooks in a dedicated global file.',
                value: agents.agentStatusHooks.grok,
                onChanged: (value) =>
                    controller.setAgentStatusHookEnabled(AgentType.grok, value),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: groupKeys['behavior'],
          child: AleraSettingsGroup(
            title: 'Behavior',
            description: 'How Alera reacts while agents are running.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Agent Status Notifications',
                description:
                    'Show native notifications when an agent needs attention. Bursts are grouped into one notification.',
                value: agents.agentStatusNotificationsEnabled,
                onChanged: (value) =>
                    controller.setAgentStatusNotificationsEnabled(value),
              ),
              SettingsSwitchRow(
                title: 'Agent Finished Notifications',
                description:
                    'Also notify when an agent finishes. Most agents report the end of a turn, not the end of a task, so this notifies on every reply.',
                value: agents.agentStatusFinishedNotificationsEnabled,
                onChanged: (value) => controller
                    .setAgentStatusFinishedNotificationsEnabled(value),
              ),
              SettingsSwitchRow(
                title: 'Keep Computer Awake While Agents Are Working',
                description: _agentAwakeSettingDescription(
                  Theme.of(context).platform,
                ),
                value: agents.keepComputerAwakeWhileAgentsWork,
                onChanged: (value) =>
                    controller.setKeepComputerAwakeWhileAgentsWork(value),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _agentAwakeSettingDescription(TargetPlatform platform) {
  if (platform == TargetPlatform.windows) {
    return 'Keeps this computer and display awake while agents are working. Lid-close behavior follows this device\'s power settings.';
  }
  return 'Keeps this computer and display awake while agents are working. Alera also asks this device to stay awake when the lid is closed, subject to its power policy.';
}

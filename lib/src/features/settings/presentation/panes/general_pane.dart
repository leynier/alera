import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/presentation/panes/agents_cli_skill_control.dart';
import 'package:alera/src/features/settings/presentation/panes/application_support_section.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:alera/src/features/updater/presentation/update_settings_section.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GeneralSettingsPane extends ConsumerWidget {
  const GeneralSettingsPane({
    super.key,
    required this.general,
    required this.agents,
  });

  final GeneralSettings general;
  final AgentSettings agents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starState = ref.watch(gitHubStarControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AleraPanel(
          children: <Widget>[
            _WorkspaceDirectoryRow(
              value: general.workspaceDirectory,
              onChanged: (next) => ref
                  .read(settingsControllerProvider.notifier)
                  .updateWorkspaceDirectory(next),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraSettingsGroup(
          title: 'Safety',
          description:
              'Confirmation prompts for destructive workspace actions.',
          children: <Widget>[
            SettingsSwitchRow(
              title: 'Confirm Project Removal',
              description:
                  'Ask before unregistering a project and deleting its workspace metadata.',
              value: general.confirmProjectRemoval,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setConfirmProjectRemoval(value),
            ),
            SettingsSwitchRow(
              title: 'Confirm Workspace Removal',
              description:
                  'Ask before removing a linked workspace and deleting its branch.',
              value: general.confirmWorkspaceRemoval,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setConfirmWorkspaceRemoval(value),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraSettingsGroup(
          title: 'Agent status',
          description: 'Managed hooks let terminal tabs show agent state.',
          children: <Widget>[
            const AleraSettingRow(
              title: 'Alera CLI Skill',
              description:
                  'Install The Codex Skill That Teaches Agents To Use The Alera CLI.',
              controlWidth: 280,
              child: AleraCliSkillControl(),
            ),
            SettingsSwitchRow(
              title: 'Codex Hooks',
              description:
                  'Use an Alera-managed Codex runtime home with status hooks.',
              value: agents.agentStatusHooks.codex,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.codex, value),
            ),
            SettingsSwitchRow(
              title: 'Claude Code Hooks',
              description:
                  'Use an Alera-managed Claude Code config with status hooks.',
              value: agents.agentStatusHooks.claude,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.claude, value),
            ),
            SettingsSwitchRow(
              title: 'GitHub Copilot Hooks',
              description: 'Use an Alera-managed GitHub Copilot home overlay.',
              value: agents.agentStatusHooks.copilot,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.copilot, value),
            ),
            SettingsSwitchRow(
              title: 'Cursor Hooks',
              description: 'Use an Alera-managed Cursor Agent plugin wrapper.',
              value: agents.agentStatusHooks.cursor,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.cursor, value),
            ),
            SettingsSwitchRow(
              title: 'Antigravity Hooks',
              description:
                  'Install Alera-managed Antigravity hooks for the agy CLI. Disable to remove only Alera-managed hook entries.',
              value: agents.agentStatusHooks.agy,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.agy, value),
            ),
            SettingsSwitchRow(
              title: 'OpenCode Hooks',
              description:
                  'Use an Alera-managed OpenCode config overlay with status plugin.',
              value: agents.agentStatusHooks.opencode,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.opencode, value),
            ),
            SettingsSwitchRow(
              title: 'Pi Hooks',
              description:
                  'Use an Alera-managed Pi agent overlay with status extension.',
              value: agents.agentStatusHooks.pi,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.pi, value),
            ),
            SettingsSwitchRow(
              title: 'Amp Hooks',
              description: 'Use an Alera-managed Amp config overlay.',
              value: agents.agentStatusHooks.amp,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.amp, value),
            ),
            SettingsSwitchRow(
              title: 'Agent Status Notifications',
              description:
                  'Show native notifications when an agent needs attention or finishes.',
              value: agents.agentStatusNotificationsEnabled,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusNotificationsEnabled(value),
            ),
            SettingsSwitchRow(
              title: 'Keep Computer Awake While Agents Are Working',
              description: _agentAwakeSettingDescription(
                Theme.of(context).platform,
              ),
              value: agents.keepComputerAwakeWhileAgentsWork,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setKeepComputerAwakeWhileAgentsWork(value),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space24),
        const UpdateSettingsSection(),
        if (starState != GitHubStarState.hidden) ...<Widget>[
          const SizedBox(height: AleraTokens.space24),
          SupportAleraSection(state: starState),
        ],
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

class _WorkspaceDirectoryRow extends StatefulWidget {
  const _WorkspaceDirectoryRow({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  State<_WorkspaceDirectoryRow> createState() => _WorkspaceDirectoryRowState();
}

class _WorkspaceDirectoryRowState extends State<_WorkspaceDirectoryRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(_WorkspaceDirectoryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        (widget.value ?? '') != _controller.text) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final next = _controller.text.trim();
    if (next.isEmpty) {
      if (widget.value != null) {
        widget.onChanged(null);
      }
      return;
    }
    if (next != widget.value) {
      widget.onChanged(next);
    }
  }

  Future<void> _browse() async {
    final picked = await getDirectoryPath(
      initialDirectory: _controller.text.isNotEmpty
          ? _controller.text
          : widget.value,
      confirmButtonText: 'Use as workspace directory',
      canCreateDirectories: true,
    );
    if (picked == null) {
      return;
    }
    _controller.text = picked;
    widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Workspace Directory',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            'Where new linked workspaces are created on disk. Existing '
            'workspaces are not moved. Leave empty to use the default '
            '(~/.alera/workspaces).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: AleraTextField(
                  controller: _controller,
                  onSubmitted: (_) => _commit(),
                  onEditingComplete: _commit,
                  hintText: '~/.alera/workspaces',
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              OutlinedButton.icon(
                onPressed: _browse,
                icon: const Icon(AleraIcons.folderOpen, size: 16),
                label: const Text('Browse'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

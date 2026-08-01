import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/design_system/surfaces/alera_command_line.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile_adapters.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_prompt_delivery.dart';
import 'package:alera/src/features/agent_profiles/domain/managed_agent_profile_options.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profile_managed_editor.dart';
import 'package:flutter/material.dart';

class AgentProfileEditor extends StatelessWidget {
  const AgentProfileEditor({
    super.key,
    required this.nameController,
    required this.commandController,
    required this.descriptionController,
    required this.quotaGroupController,
    required this.adapter,
    required this.launchMode,
    required this.managedConfig,
    required this.models,
    required this.personas,
    required this.hasSelection,
    required this.saving,
    required this.onAdapterChanged,
    required this.onLaunchModeChanged,
    required this.onManagedConfigChanged,
    required this.onRefreshModels,
    required this.onRefreshPersonas,
    required this.onSave,
    required this.onRemove,
    this.onTestCommand,
    this.modelsLoading = false,
    this.personasLoading = false,
    this.discoveryError,
    this.error,
  });

  final TextEditingController nameController;
  final TextEditingController commandController;
  final TextEditingController descriptionController;
  final TextEditingController quotaGroupController;
  final AgentType adapter;
  final AgentProfileLaunchMode launchMode;
  final Map<String, Object?> managedConfig;
  final List<ManagedAgentOption> models;
  final List<ManagedAgentOption> personas;
  final bool hasSelection;
  final bool saving;
  final bool modelsLoading;
  final bool personasLoading;
  final ValueChanged<AgentType> onAdapterChanged;
  final ValueChanged<AgentProfileLaunchMode> onLaunchModeChanged;
  final ValueChanged<Map<String, Object?>> onManagedConfigChanged;
  final VoidCallback? onRefreshModels;
  final VoidCallback? onRefreshPersonas;
  final VoidCallback onSave;
  final VoidCallback? onRemove;
  final VoidCallback? onTestCommand;
  final String? discoveryError;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final managedCommandPreview = managedAgentCommandPreview(
      adapter,
      managedConfig,
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AleraSettingsGroup(
            title: 'Profile',
            description: 'How this agent is launched for a dispatched task.',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: AleraTextField(
                  controller: nameController,
                  labelText: 'Name',
                  prefixIcon: AleraIcons.text,
                  enabled: !saving,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                ),
                child: _AgentProfileDropdown(
                  label: 'Adapter Type',
                  value: adapter,
                  onChanged: saving ? null : onAdapterChanged,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: _LaunchModeDropdown(
                  value: launchMode,
                  onChanged: saving ? null : onLaunchModeChanged,
                ),
              ),
              if (launchMode == AgentProfileLaunchMode.command) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space12,
                  ),
                  child: AleraTextField(
                    controller: commandController,
                    labelText: 'Command',
                    prefixIcon: AleraIcons.terminal,
                    enabled: !saving,
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: commandController,
                  builder: (context, value, _) => Padding(
                    padding: const EdgeInsets.only(
                      left: AleraTokens.space12,
                      right: AleraTokens.space12,
                      top: AleraTokens.space8,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: saving || value.text.trim().isEmpty
                            ? null
                            : onTestCommand,
                        icon: const Icon(AleraIcons.terminal, size: 16),
                        label: const Text('Test Command'),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AleraTokens.space12),
                  child: Text(
                    'Command mode is for advanced or unsupported CLI options. Use an interactive command that can accept a dispatch and report completion.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
                _PromptDeliveryNote(
                  adapter: adapter,
                  commandController: commandController,
                ),
              ] else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    AleraSettingRow(
                      title: 'Command Preview',
                      description:
                          'The host quotes these arguments for the actual platform shell.',
                      controlWidth: 320,
                      child: SelectableText(
                        managedCommandPreview,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AleraTokens.space12,
                        right: AleraTokens.space12,
                        top: AleraTokens.space8,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed:
                              saving || managedCommandPreview.trim().isEmpty
                              ? null
                              : onTestCommand,
                          icon: const Icon(AleraIcons.terminal, size: 16),
                          label: const Text('Test Command'),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AleraTokens.space16),
          if (launchMode == AgentProfileLaunchMode.managed) ...<Widget>[
            AgentProfileManagedEditor(
              adapter: adapter,
              config: managedConfig,
              models: models,
              personas: personas,
              enabled: !saving,
              modelsLoading: modelsLoading,
              personasLoading: personasLoading,
              discoveryError: discoveryError,
              onChanged: onManagedConfigChanged,
              onRefreshModels: onRefreshModels,
              onRefreshPersonas: onRefreshPersonas,
            ),
            if (managedAgentRiskScore(adapter, managedConfig) > 0)
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(
                      AleraIcons.warning,
                      size: 16,
                      color: AleraTokens.warning,
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: Text(
                        managedAgentRiskWarning(adapter, managedConfig),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AleraTokens.space16),
          ],
          AleraSettingsGroup(
            title: 'Routing',
            description: 'Signals the orchestrator reads when planning a run.',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: AleraTextField(
                  controller: descriptionController,
                  labelText: 'Description',
                  prefixIcon: AleraIcons.info,
                  enabled: !saving,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                ),
                child: AleraTextField(
                  controller: quotaGroupController,
                  labelText: 'Quota Group',
                  prefixIcon: AleraIcons.tag,
                  enabled: !saving,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: Text(
                  'Profiles sharing a quota group drain the same usage bucket. '
                  'Alera never measures this; it only avoids falling back '
                  'inside the same group. Leave empty if unsure.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space16),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space12),
              child: Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.error,
                ),
              ),
            ),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: <Widget>[
              // FilledButton, not ElevatedButton: the app theme styles the
              // filled, outlined and text variants, and an unthemed
              // ElevatedButton falls back to Material defaults, including a
              // cursor that resolves to `basic` on desktop.
              FilledButton.icon(
                onPressed: saving ? null : onSave,
                icon: Icon(
                  saving ? AleraIcons.loading : AleraIcons.save,
                  size: 16,
                ),
                label: Text(saving ? 'Saving' : 'Save'),
              ),
              OutlinedButton.icon(
                onPressed: hasSelection && !saving ? onRemove : null,
                icon: const Icon(AleraIcons.delete, size: 16),
                label: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How the dispatched prompt reaches the agent in Command mode, where the user
/// writes the launch line and nothing else says where the prompt goes.
class _PromptDeliveryNote extends StatelessWidget {
  const _PromptDeliveryNote({
    required this.adapter,
    required this.commandController,
  });

  final AgentType adapter;
  final TextEditingController commandController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                AleraIcons.info,
                size: 16,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space8),
              Text(
                'Prompt Delivery',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            agentPromptDeliveryDescription(adapter),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: commandController,
            builder: (context, value, _) {
              final preview = agentPromptDeliveryPreview(adapter, value.text);
              if (preview.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space12),
                child: AleraCommandLine(command: preview),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LaunchModeDropdown extends StatelessWidget {
  const _LaunchModeDropdown({required this.value, required this.onChanged});

  final AgentProfileLaunchMode value;
  final ValueChanged<AgentProfileLaunchMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Launch Mode',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space4),
        AleraDropdownField<AgentProfileLaunchMode>(
          key: ValueKey<String>('AgentProfileLaunchMode:${value.name}'),
          value: value,
          entries: const <AleraDropdownFieldEntry<AgentProfileLaunchMode>>[
            AleraDropdownFieldEntry<AgentProfileLaunchMode>(
              value: AgentProfileLaunchMode.managed,
              label: 'Managed',
            ),
            AleraDropdownFieldEntry<AgentProfileLaunchMode>(
              value: AgentProfileLaunchMode.command,
              label: 'Command',
            ),
          ],
          enabled: onChanged != null,
          onChanged: (next) => onChanged?.call(next),
        ),
      ],
    );
  }
}

class _AgentProfileDropdown extends StatelessWidget {
  const _AgentProfileDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final AgentType value;
  final ValueChanged<AgentType>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space4),
        AleraDropdownField<AgentType>(
          key: ValueKey<String>('AgentProfileAdapter:${value.key}'),
          value: value,
          entries: <AleraDropdownFieldEntry<AgentType>>[
            for (final option in spawnableAgentProfileAdapters)
              AleraDropdownFieldEntry<AgentType>(
                value: option,
                label: agentDisplayName(option),
              ),
          ],
          enabled: onChanged != null,
          onChanged: (next) => onChanged?.call(next),
        ),
      ],
    );
  }
}

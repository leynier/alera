import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile_adapters.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';

class AgentProfileEditor extends StatelessWidget {
  const AgentProfileEditor({
    super.key,
    required this.nameController,
    required this.commandController,
    required this.descriptionController,
    required this.quotaGroupController,
    required this.adapter,
    required this.hasSelection,
    required this.saving,
    required this.onAdapterChanged,
    required this.onSave,
    required this.onRemove,
    this.error,
  });

  final TextEditingController nameController;
  final TextEditingController commandController;
  final TextEditingController descriptionController;
  final TextEditingController quotaGroupController;
  final AgentType adapter;
  final bool hasSelection;
  final bool saving;
  final ValueChanged<AgentType> onAdapterChanged;
  final VoidCallback onSave;
  final VoidCallback? onRemove;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AleraSettingsGroup(
            title: 'Profile',
            description: 'How This Agent Is Launched For A Dispatched Task.',
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
                child: AleraTextField(
                  controller: commandController,
                  labelText: 'Command',
                  prefixIcon: AleraIcons.terminal,
                  enabled: !saving,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: AleraTokens.space12,
                  right: AleraTokens.space12,
                  bottom: AleraTokens.space12,
                ),
                child: Text(
                  'Use The Interactive Form Of The Command. A One-Shot Mode '
                  'Cannot Accept A Dispatch Or Report Completion.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space16),
          AleraSettingsGroup(
            title: 'Routing',
            description: 'Signals The Orchestrator Reads When Planning A Run.',
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
                  'Profiles Sharing A Quota Group Drain The Same Usage Bucket. '
                  'Alera Never Measures This; It Only Avoids Falling Back '
                  'Inside The Same Group. Leave Empty If Unsure.',
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
              ElevatedButton.icon(
                onPressed: saving ? null : onSave,
                icon: Icon(saving ? AleraIcons.loading : AleraIcons.save),
                label: const Text('Save'),
              ),
              OutlinedButton.icon(
                onPressed: hasSelection && !saving ? onRemove : null,
                icon: const Icon(AleraIcons.delete),
                label: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
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

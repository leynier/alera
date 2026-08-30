import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';

class TextActionEditor extends StatelessWidget {
  const TextActionEditor({
    super.key,
    required this.nameController,
    required this.promptController,
    required this.enabled,
    required this.agentOverride,
    required this.modelOverride,
    required this.reasoningByModel,
    required this.aiAssistSettings,
    required this.error,
    required this.onEnabledChanged,
    required this.onAgentChanged,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.onSave,
    required this.onDelete,
    required this.isNew,
  });

  final TextEditingController nameController;
  final TextEditingController promptController;
  final bool enabled;
  final AiAssistAgent? agentOverride;
  final String? modelOverride;
  final Map<String, String> reasoningByModel;
  final AiAssistSettings aiAssistSettings;
  final String? error;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<AiAssistAgent?> onAgentChanged;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String?> onReasoningChanged;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final agent = agentOverride ?? aiAssistSettings.agent;
    final models = modelsForAgent(agent, aiAssistSettings);
    final globalModelId =
        aiAssistSettings.modelFor(agent) ??
        defaultModelIdForAgent(agent, aiAssistSettings);
    final effectiveModelId = modelOverride?.trim().isNotEmpty == true
        ? modelOverride
        : globalModelId;
    final model = modelForAgent(
      agent,
      effectiveModelId,
      extraModels: discoveredModelsForAgent(aiAssistSettings, agent),
    );
    final reasoningLevels = model.thinkingLevels;
    final reasoningValue = reasoningByModel[model.id];
    final inheritedReasoning =
        aiAssistSettings.thinkingForModel(model.id) ??
        model.defaultThinkingLevel ??
        (reasoningLevels.isEmpty ? null : reasoningLevels.first.id);
    final inheritedReasoningLabel = reasoningLevels
        .where((level) => level.id == inheritedReasoning)
        .firstOrNull
        ?.label;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AleraSettingsGroup(
            title: 'Action',
            description:
                'Define the reusable instruction and its availability.',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: AleraTextField(
                  controller: nameController,
                  labelText: 'Name',
                  prefixIcon: AleraIcons.text,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: AleraTokens.space12,
                  right: AleraTokens.space12,
                  bottom: AleraTokens.space12,
                ),
                child: AleraTextField(
                  controller: promptController,
                  labelText: 'Prompt',
                  hintText: 'Describe the replacement to generate.',
                  minLines: 5,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                ),
              ),
              SettingsSwitchRow(
                title: 'Enabled',
                description: 'Show this action in the Text Actions menu.',
                value: enabled,
                onChanged: onEnabledChanged,
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space16),
          AleraSettingsGroup(
            title: 'Agent',
            description: 'Choose which CLI and model run this action.',
            children: <Widget>[
              AleraSettingRow(
                title: 'Agent',
                description: 'Inherit the global AI Assist agent by default.',
                child: AleraDropdownField<AiAssistAgent?>(
                  value: agentOverride,
                  entries: <AleraDropdownFieldEntry<AiAssistAgent?>>[
                    AleraDropdownFieldEntry<AiAssistAgent?>(
                      value: null,
                      label: 'Global (${aiAssistSettings.agent.label})',
                    ),
                    for (final candidate in AiAssistAgent.values)
                      AleraDropdownFieldEntry<AiAssistAgent?>(
                        value: candidate,
                        label: candidate.label,
                      ),
                  ],
                  onChanged: onAgentChanged,
                ),
              ),
              AleraSettingRow(
                title: 'Model',
                description: 'Inherit the selected model unless overridden.',
                child: AleraDropdownField<String?>(
                  value: modelOverride,
                  entries: <AleraDropdownFieldEntry<String?>>[
                    AleraDropdownFieldEntry<String?>(
                      value: null,
                      label: 'Global ($globalModelId)',
                    ),
                    for (final candidate in models)
                      AleraDropdownFieldEntry<String?>(
                        value: candidate.id,
                        label: candidate.id.isEmpty
                            ? candidate.label
                            : candidate.label,
                      ),
                  ],
                  onChanged: onModelChanged,
                ),
              ),
              if (reasoningLevels.isNotEmpty)
                AleraSettingRow(
                  title: 'Reasoning',
                  description: 'Reasoning effort for the effective model.',
                  child: AleraDropdownField<String?>(
                    value: reasoningValue,
                    entries: <AleraDropdownFieldEntry<String?>>[
                      AleraDropdownFieldEntry<String?>(
                        value: null,
                        label: inheritedReasoningLabel == null
                            ? 'Global'
                            : 'Global ($inheritedReasoningLabel)',
                      ),
                      for (final level in reasoningLevels)
                        AleraDropdownFieldEntry<String?>(
                          value: level.id,
                          label: level.label,
                        ),
                    ],
                    onChanged: onReasoningChanged,
                  ),
                ),
            ],
          ),
          if (error case final error?) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.error),
            ),
          ],
          const SizedBox(height: AleraTokens.space16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (!isNew)
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(AleraIcons.delete, size: 16),
                  style: TextButton.styleFrom(
                    foregroundColor: AleraTokens.error,
                  ),
                  label: const Text('Delete'),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(AleraIcons.save, size: 16),
                label: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

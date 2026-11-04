import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_provider_model_picker.dart';
import 'package:alera/src/design_system/layout/alera_sectioned_picker.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_model_picker.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_settings.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The provider a new child chat starts with when the person has not picked
/// one: the first available instance of the runtime's catalog.
AgentChatProviderInstance? chatTaskDefaultProvider(
  AgentChatOrchestrationCapabilities catalog,
) => catalog.providers.where((provider) => provider.available).firstOrNull;

/// The agent of a new child chat, from the runtime's own catalog: nothing is
/// listed that the runtime did not report.
class const DelegateChatTaskAgentFields({
  super.key,
  required final AgentChatOrchestrationCapabilities catalog,
  required final AgentChatDelegateDraft draft,
  required final ValueChanged<AgentChatDelegateDraftEdit> onEdit,
  final bool enabled = true,
  final bool effortSupported = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider =
        catalog.providers
            .where((item) => item.id == draft.providerInstanceId)
            .firstOrNull ??
        chatTaskDefaultProvider(catalog);
    if (provider == null) {
      return Text(
        'This runtime has no agent available for chats.',
        style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.error),
      );
    }
    final ceiling = catalog.ceilingRuntimeModes;
    final modes = <AgentChatRuntimeMode>[
      for (final mode in provider.runtimeModes)
        if (ceiling.isEmpty || ceiling.contains(mode)) mode,
    ];
    final support = catalog.supportFor(provider.id);
    final selected = AgentChatSelection(
      providerInstanceId: provider.id,
      model: draft.providerInstanceId == provider.id
          ? draft.model
          : provider.initialModel?.id,
    );
    final model = provider.modelById(selected.model);
    final efforts = model?.reasoningEfforts ?? const <String>[];
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        // The same grouped picker the composer uses, so an agent and model
        // read and search alike wherever a chat is started.
        AleraProviderModelPicker<AgentChatSelection>(
          key: const ValueKey<String>('delegateAgent'),
          label:
              '${provider.label} · '
              '${agentChatModelLabel(provider, selected.model)}',
          leading: AgentChatProviderIcon(provider: provider.provider),
          tooltip: 'Choose Agent And Model',
          enabled: enabled,
          selectedValue: selected,
          sections: <AleraPickerSection<AgentChatSelection>>[
            for (final group in agentChatPickerGroups(
              providers: catalog.providers,
              currentSelection: selected,
            ))
              AleraPickerSection<AgentChatSelection>(
                title: group.instance.label,
                rows: <AleraPickerRow<AgentChatSelection>>[
                  for (final row in group.rows)
                    AleraPickerRow<AgentChatSelection>(
                      value: row.selection,
                      title: row.model.label,
                      subtitle: agentChatModelSubtitle(row.model),
                      disabledReason: row.enabled
                          ? null
                          : row.disabledReason ?? 'Unavailable',
                      keywords: <String>[group.instance.label, ?row.model.id],
                    ),
                ],
              ),
          ],
          onSelected: (pick) => onEdit(
            (draft) => pick.providerInstanceId == provider.id
                ? draft.copyWith(
                    providerInstanceId: provider.id,
                    model: pick.model,
                    reasoningEffort: null,
                  )
                : draft.copyWith(
                    providerInstanceId: pick.providerInstanceId,
                    model: pick.model,
                    reasoningEffort: null,
                    runtimeMode: null,
                    plan: false,
                  ),
          ),
        ),
        if (effortSupported && efforts.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          AleraDropdownField<String?>(
            key: const ValueKey<String>('delegateEffort'),
            value: efforts.contains(draft.reasoningEffort)
                ? draft.reasoningEffort
                : null,
            labelText: 'Reasoning Effort',
            enabled: enabled,
            entries: <AleraDropdownFieldEntry<String?>>[
              AleraDropdownFieldEntry<String?>(
                value: null,
                label: switch (model?.defaultReasoningEffort) {
                  final effort? =>
                    'Model Default (${agentChatEffortLabel(effort)})',
                  null => 'Model Default',
                },
              ),
              for (final effort in efforts)
                AleraDropdownFieldEntry<String?>(
                  value: effort,
                  label: agentChatEffortLabel(effort),
                ),
            ],
            onChanged: (effort) => onEdit(
              (draft) => draft.copyWith(
                providerInstanceId: provider.id,
                model: selected.model,
                reasoningEffort: effort,
              ),
            ),
          ),
        ],
        if (modes.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          AleraDropdownField<AgentChatRuntimeMode?>(
            key: const ValueKey<String>('delegateRuntimeMode'),
            value: modes.contains(draft.runtimeMode) ? draft.runtimeMode : null,
            labelText: 'Runtime Mode',
            enabled: enabled,
            entries: <AleraDropdownFieldEntry<AgentChatRuntimeMode?>>[
              const AleraDropdownFieldEntry<AgentChatRuntimeMode?>(
                value: null,
                label: 'Runtime Default',
              ),
              for (final mode in modes)
                AleraDropdownFieldEntry<AgentChatRuntimeMode?>(
                  value: mode,
                  label: agentChatRuntimeModeLabel(mode),
                ),
            ],
            onChanged: (mode) => onEdit(
              (draft) => draft.copyWith(
                providerInstanceId: provider.id,
                runtimeMode: mode,
              ),
            ),
          ),
        ],
        if (provider.supportsPlanMode) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          AleraCheckbox(
            value: draft.plan,
            label: 'Plan First',
            enabled: enabled,
            onChanged: (value) => onEdit(
              (draft) =>
                  draft.copyWith(providerInstanceId: provider.id, plan: value),
            ),
          ),
        ],
        if (support != null && !support.supported) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          Text(
            support.reason ??
                'This agent runs the task but cannot delegate further.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ],
    );
  }
}

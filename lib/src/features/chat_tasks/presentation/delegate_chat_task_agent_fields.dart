import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
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
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraDropdownField<String>(
          key: const ValueKey<String>('delegateAgent'),
          value: provider.id,
          labelText: 'Agent',
          enabled: enabled,
          filterable: catalog.providers.length > 8,
          entries: <AleraDropdownFieldEntry<String>>[
            for (final item in catalog.providers)
              AleraDropdownFieldEntry<String>(
                value: item.id,
                label: item.label,
                enabled: item.available,
                detail: item.available ? null : item.unavailableReason,
              ),
          ],
          onChanged: (id) {
            final next = catalog.providers.firstWhere((item) => item.id == id);
            onEdit(
              (draft) => draft.copyWith(
                providerInstanceId: id,
                model: next.initialModel?.id,
                runtimeMode: null,
                plan: false,
              ),
            );
          },
        ),
        if (provider.models.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          AleraDropdownField<String>(
            key: const ValueKey<String>('delegateModel'),
            value:
                provider.modelById(draft.model)?.id ??
                provider.initialModel?.id,
            labelText: 'Model',
            enabled: enabled,
            filterable: provider.models.length > 8,
            entries: <AleraDropdownFieldEntry<String>>[
              for (final model in provider.models)
                AleraDropdownFieldEntry<String>(
                  value: model.id,
                  label: model.label,
                ),
            ],
            onChanged: (id) => onEdit(
              (draft) =>
                  draft.copyWith(providerInstanceId: provider.id, model: id),
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

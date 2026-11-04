import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_provider_model_picker.dart';
import 'package:alera/src/design_system/layout/alera_sectioned_picker.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_model_picker.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_settings.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera/src/features/automations/application/automation_agent_chats.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Label of the chat choice that starts a new chat for every run.
const String automationNewChatEachRunLabel = 'New Chat Each Run';

/// What an agent chat destination still needs: the chat every run posts
/// into, or the agent, model and effort a new chat per run starts with, and
/// the most access a run may have.
class const AutomationAgentChatFields({
  required final AutomationComposerControllerProvider provider,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(provider.select((state) => state.draft.agentChat));
    final workspaceId = target.workspaceId;
    if (workspaceId == null) return const SizedBox.shrink();
    final controller = ref.read(provider.notifier);
    void edit(
      AutomationAgentChatTarget Function(AutomationAgentChatTarget target)
      change,
    ) => controller.update(
      (draft) => draft.withAgentChat(change(draft.agentChat)),
    );
    final chats = ref.watch(automationAgentChatsProvider(workspaceId));
    final catalog = ref.watch(agentChatProviderCatalogProvider(workspaceId));
    final providers = catalog.value ?? const <AgentChatProviderInstance>[];
    final listed = chats.value ?? const <AgentChatSummary>[];
    final chatId = target.chatId;
    final instance = providers
        .where((item) => item.id == target.providerInstanceId)
        .firstOrNull;
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final chatEntries = <AleraDropdownFieldEntry<String?>>[
      const AleraDropdownFieldEntry<String?>(
        value: null,
        label: automationNewChatEachRunLabel,
      ),
      if (chatId != null && !listed.any((chat) => chat.chatId == chatId))
        AleraDropdownFieldEntry<String?>(value: chatId, label: 'Stored Chat'),
      for (final chat in listed)
        AleraDropdownFieldEntry<String?>(
          value: chat.chatId,
          label: chat.title.trim().isEmpty ? 'Untitled Chat' : chat.title,
        ),
    ];
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      spacing: AleraTokens.space8,
      children: <Widget>[
        AleraDropdownField<String?>(
          key: const ValueKey<String>('automation-agent-chat'),
          labelText: 'Chat',
          value: chatId,
          hintText: chats.isLoading ? 'Loading chats...' : null,
          filterable: chatEntries.length > 8,
          filterHintText: 'Search Chats',
          entries: chatEntries,
          onChanged: (value) => edit(
            (current) =>
                value == null ? current.newChat() : current.boundTo(value),
          ),
        ),
        if (chats.hasError)
          Text(
            'Could not load the chats of this workspace.',
            style: muted?.copyWith(color: AleraTokens.error),
          ),
        if (target.newChatEachRun)
          _NewChatAgent(
            target: target,
            providers: providers,
            loading: catalog.isLoading && !catalog.hasValue,
            onEdit: edit,
          ),
        _ModeCeilingField(
          target: target,
          modes: instance?.runtimeModes ?? AgentChatRuntimeMode.values,
          onEdit: edit,
        ),
        Text(
          target.newChatEachRun
              ? 'Each run starts a new chat in this workspace.'
              : 'Each run posts its prompt into this chat.',
          style: muted,
        ),
      ],
    );
  }
}

class const _NewChatAgent({
  required final AutomationAgentChatTarget target,
  required final List<AgentChatProviderInstance> providers,
  required final bool loading,
  required final ValueChanged<
    AutomationAgentChatTarget Function(AutomationAgentChatTarget)
  >
  onEdit,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final instance = providers
        .where((item) => item.id == target.providerInstanceId)
        .firstOrNull;
    final selected = target.providerInstanceId == null
        ? null
        : AgentChatSelection(
            providerInstanceId: target.providerInstanceId!,
            model: target.model,
          );
    final model = target.model == null
        ? instance?.initialModel
        : instance?.modelById(target.model);
    final efforts = model?.reasoningEfforts ?? const <String>[];
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      spacing: AleraTokens.space8,
      children: <Widget>[
        AleraProviderModelPicker<AgentChatSelection>(
          key: const ValueKey<String>('automation-agent-chat-agent'),
          label: selected == null
              ? 'Choose Agent'
              : '${instance?.label ?? target.provider ?? selected.providerInstanceId}'
                    ' · ${agentChatModelLabel(instance, selected.model)}',
          leading: instance == null
              ? null
              : AgentChatProviderIcon(provider: instance.provider),
          tooltip: 'Choose Agent And Model',
          loading: loading,
          selectedValue: selected,
          sections: <AleraPickerSection<AgentChatSelection>>[
            for (final group in agentChatPickerGroups(
              providers: providers,
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
          onSelected: (pick) {
            final picked = providers
                .where((item) => item.id == pick.providerInstanceId)
                .firstOrNull;
            if (picked == null) return;
            onEdit(
              (current) => current.pickAgent(
                provider: picked.provider,
                providerInstanceId: picked.id,
                model: pick.model,
                modes: <String>[
                  for (final mode in picked.runtimeModes) mode.wire,
                ],
              ),
            );
          },
        ),
        if (efforts.isNotEmpty)
          AleraDropdownField<String?>(
            key: const ValueKey<String>('automation-agent-chat-effort'),
            labelText: 'Reasoning Effort',
            value: efforts.contains(target.reasoningEffort)
                ? target.reasoningEffort
                : null,
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
            onChanged: (effort) =>
                onEdit((current) => current.withReasoningEffort(effort)),
          ),
      ],
    );
  }
}

class const _ModeCeilingField({
  required final AutomationAgentChatTarget target,
  required final List<AgentChatRuntimeMode> modes,
  required final ValueChanged<
    AutomationAgentChatTarget Function(AutomationAgentChatTarget)
  >
  onEdit,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ceiling = target.runtimeModeCeiling;
    final offered = modes.isEmpty ? AgentChatRuntimeMode.values : modes;
    final entries = <AleraDropdownFieldEntry<String?>>[
      if (ceiling == null)
        const AleraDropdownFieldEntry<String?>(
          value: null,
          label: 'Chat Default',
        ),
      if (ceiling != null && !offered.any((mode) => mode.wire == ceiling))
        AleraDropdownFieldEntry<String?>(
          value: ceiling,
          label: switch (AgentChatRuntimeMode.tryParse(ceiling)) {
            final mode? => agentChatRuntimeModeLabel(mode),
            null => ceiling,
          },
        ),
      for (final mode in offered)
        AleraDropdownFieldEntry<String?>(
          value: mode.wire,
          label: agentChatRuntimeModeLabel(mode),
        ),
    ];
    return AleraDropdownField<String?>(
      key: const ValueKey<String>('automation-agent-chat-ceiling'),
      labelText: 'Most Access',
      value: ceiling,
      entries: entries,
      onChanged: (mode) =>
          onEdit((current) => current.withRuntimeModeCeiling(mode)),
    );
  }
}

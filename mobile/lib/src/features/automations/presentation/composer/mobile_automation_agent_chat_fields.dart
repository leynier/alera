import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_model_picker_sheet.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_agent_chats.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Label of the chat choice that starts a new chat for every run.
const String mobileAutomationNewChatEachRunLabel = 'New Chat Each Run';

/// What an agent chat destination still needs: the chat every run posts
/// into, or the agent, model and effort a new chat per run starts with, and
/// the most access a run may have.
class const MobileAutomationAgentChatFields({
  required final MobileAutomationComposerControllerProvider provider,
  required final String hostId,
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
    final chats = ref.watch(
      mobileAutomationAgentChatsProvider(hostId, workspaceId),
    );
    final catalog = ref.watch(agentChatProvidersProvider(hostId, workspaceId));
    final providers = catalog.value ?? const <AgentChatProviderInstance>[];
    final listed = chats.value ?? const <AgentChatSummary>[];
    final chatId = target.chatId;
    final instance = providers
        .where((item) => item.id == target.providerInstanceId)
        .firstOrNull;
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final model = target.model == null
        ? instance?.initialModel
        : instance?.modelById(target.model);
    final efforts = model?.reasoningEfforts ?? const <String>[];
    final chatEntries = <AleraDropdownFieldEntry<String?>>[
      const AleraDropdownFieldEntry<String?>(
        value: null,
        label: mobileAutomationNewChatEachRunLabel,
      ),
      if (chatId != null && !listed.any((chat) => chat.chatId == chatId))
        AleraDropdownFieldEntry<String?>(value: chatId, label: 'Stored Chat'),
      for (final chat in listed)
        AleraDropdownFieldEntry<String?>(
          value: chat.chatId,
          label: chat.title.trim().isEmpty ? 'Untitled Chat' : chat.title,
        ),
    ];
    final modes = instance?.runtimeModes.isNotEmpty == true
        ? instance!.runtimeModes
        : AgentChatRuntimeMode.values;
    final ceiling = target.runtimeModeCeiling;
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      spacing: AleraTokens.spaceSm,
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
        if (target.newChatEachRun) ...<Widget>[
          OutlinedButton.icon(
            key: const ValueKey<String>('automation-agent-chat-agent'),
            icon: const Icon(AleraIcons.agent, size: AleraTokens.iconMd),
            label: Text(
              target.providerInstanceId == null
                  ? 'Choose Agent'
                  : '${instance?.label ?? target.provider} · '
                        '${model?.label ?? target.model ?? agentChatProviderDefaultLabel}',
            ),
            onPressed: catalog.hasValue
                ? () => unawaited(_pickAgent(context, providers, target, edit))
                : null,
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
                  edit((current) => current.withReasoningEffort(effort)),
            ),
        ],
        AleraDropdownField<String?>(
          key: const ValueKey<String>('automation-agent-chat-ceiling'),
          labelText: 'Most Access',
          value: ceiling,
          entries: <AleraDropdownFieldEntry<String?>>[
            if (ceiling == null)
              const AleraDropdownFieldEntry<String?>(
                value: null,
                label: 'Chat Default',
              ),
            if (ceiling != null && !modes.any((mode) => mode.wire == ceiling))
              AleraDropdownFieldEntry<String?>(value: ceiling, label: ceiling),
            for (final mode in modes)
              AleraDropdownFieldEntry<String?>(
                value: mode.wire,
                label: agentChatRuntimeModeLabel(mode),
              ),
          ],
          onChanged: (mode) =>
              edit((current) => current.withRuntimeModeCeiling(mode)),
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

  Future<void> _pickAgent(
    BuildContext context,
    List<AgentChatProviderInstance> providers,
    AutomationAgentChatTarget target,
    void Function(
      AutomationAgentChatTarget Function(AutomationAgentChatTarget target),
    )
    edit,
  ) async {
    final picked = await showAgentChatModelPicker(
      context,
      providers: providers,
      preferences: const AgentChatPreferences(),
      current: target.providerInstanceId == null
          ? null
          : AgentChatSelection(
              providerInstanceId: target.providerInstanceId!,
              model: target.model,
            ),
      canSwitchProvider: true,
    );
    if (picked == null) return;
    final instance = providers
        .where((item) => item.id == picked.providerInstanceId)
        .firstOrNull;
    if (instance == null) return;
    edit(
      (current) => current.pickAgent(
        provider: instance.provider,
        providerInstanceId: instance.id,
        model: picked.model,
        modes: <String>[for (final mode in instance.runtimeModes) mode.wire],
      ),
    );
  }
}

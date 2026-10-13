import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_mode_labels.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';

/// What the settings sheet shows for the chat as it is now.
class const AgentChatSettingsCurrent({
  required final String providerInstanceId,
  required final String? model,
  required final AgentChatRuntimeMode runtimeMode,
  required final AgentChatInteractionMode interactionMode,
  required final bool canSwitchProvider,
});

/// Agent, model, approvals and plan mode for the next turn. Each choice is
/// sent on its own; the runtime refuses what the provider cannot honor, and
/// refuses a provider switch while anything is still running.
Future<void> showAgentChatSettingsSheet(
  BuildContext context, {
  required List<AgentChatProviderInstance> providers,
  required AgentChatSettingsCurrent current,
  required Future<void> Function(AgentChatConfiguration configuration)
  onConfigure,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: AgentChatSettingsPanel(
        providers: providers,
        current: current,
        onConfigure: (configuration) async {
          Navigator.of(context).pop();
          await onConfigure(configuration);
        },
      ),
    ),
  ),
);

class const AgentChatSettingsPanel({
  super.key,
  required final List<AgentChatProviderInstance> providers,
  required final AgentChatSettingsCurrent current,
  required final Future<void> Function(AgentChatConfiguration) onConfigure,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    AgentChatProviderInstance? instance;
    for (final candidate in providers) {
      if (candidate.id == current.providerInstanceId) instance = candidate;
    }
    final models = instance?.models ?? const <AgentChatModelOption>[];
    final modelSwitch = instance?.capabilities.modelSwitch ?? false;
    final runtimeModes =
        instance?.runtimeModes ?? const <AgentChatRuntimeMode>[];
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        if (providers.length > 1) ...<Widget>[
          const AleraSectionHeader(label: 'Agent'),
          if (!current.canSwitchProvider)
            const ListTile(
              dense: true,
              subtitle: Text(
                'Switch agents once the current turn, requests and queued '
                'messages have finished.',
              ),
            ),
          for (final provider in providers)
            ListTile(
              minTileHeight: AleraTokens.minTapTarget,
              leading: AgentIdentityIcon(
                agentType: agentChatAgentType(provider.provider),
                size: AleraTokens.space20,
                showTooltip: false,
              ),
              title: Text(provider.label),
              subtitle: provider.available
                  ? null
                  : Text(provider.unavailableReason ?? 'Not available'),
              trailing: provider.id == current.providerInstanceId
                  ? const Icon(AleraIcons.check)
                  : null,
              enabled:
                  provider.available &&
                  current.canSwitchProvider &&
                  provider.id != current.providerInstanceId,
              onTap: () => unawaited(
                onConfigure(
                  AgentChatConfiguration(providerInstanceId: provider.id),
                ),
              ),
            ),
        ],
        if (models.length > 1 && modelSwitch) ...<Widget>[
          const AleraSectionHeader(label: 'Model'),
          for (final model in models)
            ListTile(
              minTileHeight: AleraTokens.minTapTarget,
              title: Text(model.label),
              trailing: model.id == current.model
                  ? const Icon(AleraIcons.check)
                  : null,
              onTap: model.id == current.model
                  ? null
                  : () => unawaited(
                      onConfigure(AgentChatConfiguration(model: model.id)),
                    ),
            ),
        ],
        if (runtimeModes.length > 1) ...<Widget>[
          const AleraSectionHeader(label: 'Approvals'),
          for (final mode in runtimeModes)
            ListTile(
              minTileHeight: AleraTokens.minTapTarget,
              leading: Icon(
                agentChatRuntimeModeIcon(mode),
                color: mode == AgentChatRuntimeMode.fullAccess
                    ? AleraTokens.warning
                    : null,
              ),
              title: Text(agentChatRuntimeModeLabel(mode)),
              subtitle: Text(agentChatRuntimeModeDescription(mode)),
              trailing: mode == current.runtimeMode
                  ? const Icon(AleraIcons.check)
                  : null,
              onTap: mode == current.runtimeMode
                  ? null
                  : () => unawaited(_selectMode(context, mode)),
            ),
        ],
        if (instance?.supportsPlanMode ?? false)
          SwitchListTile(
            title: const Text('Plan Mode'),
            subtitle: const Text(
              'The agent proposes a plan and waits before changing anything.',
            ),
            value: current.interactionMode == AgentChatInteractionMode.plan,
            onChanged: (plan) => unawaited(
              onConfigure(
                AgentChatConfiguration(
                  interactionMode: plan
                      ? AgentChatInteractionMode.plan
                      : AgentChatInteractionMode.standard,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _selectMode(
    BuildContext context,
    AgentChatRuntimeMode mode,
  ) async {
    if (mode == AgentChatRuntimeMode.fullAccess &&
        !await _confirmFullAccess(context)) {
      return;
    }
    await onConfigure(AgentChatConfiguration(runtimeMode: mode));
  }
}

Future<bool> _confirmFullAccess(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(AleraIcons.warning, color: AleraTokens.warning),
        title: const Text('Turn On Full Access?'),
        content: const Text(
          'The agent will be able to run commands, use the network, and '
          'create, edit or delete files on the host without asking.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn On'),
          ),
        ],
      ),
    ) ??
    false;

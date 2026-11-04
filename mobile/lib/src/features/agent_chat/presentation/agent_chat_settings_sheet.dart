import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_mode_labels.dart';
import 'package:flutter/material.dart';

/// What the settings sheet shows for the chat as it is now.
class const AgentChatSettingsCurrent({
  required final AgentChatRuntimeMode runtimeMode,
  required final AgentChatInteractionMode interactionMode,
  final AgentChatProviderInstance? instance,
  final AgentChatModelOption? model,
  final String? reasoningEffort,
  final bool effortSupported = false,
  final bool? fileCheckpointing,
  final bool canChangeFileCheckpointing = false,
});

/// Approvals, plan mode and, where the model reports it, reasoning effort
/// for the next turn. The agent and model are picked from the composer chip.
/// Each choice is sent on its own; the runtime refuses what the provider
/// cannot honor.
Future<void> showAgentChatSettingsSheet(
  BuildContext context, {
  required AgentChatSettingsCurrent current,
  required Future<void> Function(AgentChatConfiguration configuration)
  onConfigure,
  Future<void> Function(bool enabled)? onFileCheckpointing,
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
        current: current,
        onConfigure: (configuration) async {
          Navigator.of(context).pop();
          await onConfigure(configuration);
        },
        onFileCheckpointing: onFileCheckpointing == null
            ? null
            : (enabled) async {
                Navigator.of(context).pop();
                await onFileCheckpointing(enabled);
              },
      ),
    ),
  ),
);

class const AgentChatSettingsPanel({
  super.key,
  required final AgentChatSettingsCurrent current,
  required final Future<void> Function(AgentChatConfiguration) onConfigure,
  final Future<void> Function(bool enabled)? onFileCheckpointing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final instance = current.instance;
    final runtimeModes =
        instance?.runtimeModes ?? const <AgentChatRuntimeMode>[];
    final efforts = current.effortSupported
        ? current.model?.reasoningEfforts ?? const <String>[]
        : const <String>[];
    final effort =
        current.reasoningEffort ?? current.model?.defaultReasoningEffort;
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
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
        // Shown whenever the agent supports it, on or off; it only changes
        // while the chat is idle, and takes effect with the next message.
        if (current.fileCheckpointing case final enabled?)
          SwitchListTile(
            title: const Text('File Checkpointing'),
            subtitle: Text(
              current.canChangeFileCheckpointing
                  ? 'Save file checkpoints so a rewind can restore files. '
                        'Applies from the next message, which starts a new '
                        'agent session.'
                  : 'Change this once the current turn ends and nothing is '
                        'pending.',
            ),
            value: enabled,
            onChanged:
                current.canChangeFileCheckpointing &&
                    onFileCheckpointing != null
                ? (on) => unawaited(onFileCheckpointing!(on))
                : null,
          ),
        if (efforts.isNotEmpty) ...<Widget>[
          const AleraSectionHeader(label: 'Reasoning Effort'),
          for (final option in efforts)
            ListTile(
              minTileHeight: AleraTokens.minTapTarget,
              title: Text(agentChatEffortLabel(option)),
              subtitle: option == current.model?.defaultReasoningEffort
                  ? const Text('Model default')
                  : null,
              trailing: option == effort ? const Icon(AleraIcons.check) : null,
              onTap: option == effort
                  ? null
                  : () => unawaited(
                      onConfigure(
                        option == current.model?.defaultReasoningEffort
                            ? const AgentChatConfiguration(
                                resetReasoningEffort: true,
                              )
                            : AgentChatConfiguration(reasoningEffort: option),
                      ),
                    ),
            ),
        ],
      ],
    );
  }

  Future<void> _selectMode(
    BuildContext context,
    AgentChatRuntimeMode mode,
  ) async {
    if (mode == AgentChatRuntimeMode.fullAccess &&
        !await confirmAgentChatFullAccess(context)) {
      return;
    }
    await onConfigure(AgentChatConfiguration(runtimeMode: mode));
  }
}

/// The same confirmation the desktop asks before Full Access.
Future<bool> confirmAgentChatFullAccess(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => const AleraConfirmDialog(
        title: agentChatFullAccessTitle,
        message: agentChatFullAccessMessage,
        confirmLabel: agentChatFullAccessConfirm,
      ),
    ) ??
    false;

/// Asked only once a chat has history to hand over; an empty chat switches
/// without a question.
Future<bool> confirmAgentChatSwitch(BuildContext context, String agent) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AleraConfirmDialog(
        title: agentChatSwitchAgentTitle(agent),
        message: agentChatSwitchAgentMessage(agent),
        confirmLabel: agentChatSwitchAgentConfirm,
      ),
    ) ??
    false;

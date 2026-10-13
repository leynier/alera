import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The settings the composer shows for the chat's next turn.
final class const AgentChatComposerSettings({
  required final String provider,
  required final String providerInstanceId,
  required final AgentChatSession session,
  required final List<AgentChatProviderInstance> providers,
  required final bool canSwitchProvider,
  required final bool configuring,
}) {
  AgentChatProviderInstance? get instance {
    for (final candidate in providers) {
      if (candidate.id == providerInstanceId) return candidate;
    }
    return null;
  }

  String get providerLabel =>
      instance?.label ?? agentChatProviderFallbackLabel(provider);
}

String agentChatRuntimeModeLabel(AgentChatRuntimeMode mode) => switch (mode) {
  AgentChatRuntimeMode.approvalRequired => 'Ask For Approval',
  AgentChatRuntimeMode.autoAcceptEdits => 'Accept Edits',
  AgentChatRuntimeMode.auto => 'Auto',
  AgentChatRuntimeMode.fullAccess => 'Full Access',
};

String _runtimeModeDescription(AgentChatRuntimeMode mode) => switch (mode) {
  AgentChatRuntimeMode.approvalRequired =>
    'Ask before running commands or changing files.',
  AgentChatRuntimeMode.autoAcceptEdits =>
    'Change files without asking; ask before running commands.',
  AgentChatRuntimeMode.auto => 'Let the agent decide when to ask.',
  AgentChatRuntimeMode.fullAccess =>
    'Run commands and change any file without asking.',
};

/// Provider, model, approval mode and plan mode for the next turn.
class const AgentChatComposerControls({
  super.key,
  required final AgentChatComposerSettings settings,
  required final bool enabled,
  required final ValueChanged<AgentChatConfiguration> onConfigure,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = settings.session;
    final instance = settings.instance;
    final models = instance?.models ?? const <AgentChatModelOption>[];
    final runtimeModes =
        instance?.runtimeModes ?? const <AgentChatRuntimeMode>[];
    final planSupported =
        instance?.supportsPlanMode ?? session.capabilities.plan;
    final ready = enabled && !settings.configuring;
    final model = instance?.modelById(session.model);
    final planMode = session.interactionMode == AgentChatInteractionMode.plan;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AgentChatComposerChip(
          key: const ValueKey<String>('agent-chat-provider-chip'),
          leading: AgentChatProviderIcon(provider: settings.provider),
          label: settings.providerLabel,
          tooltip: settings.canSwitchProvider
              ? 'Switch Provider'
              : 'The provider can change once the agent is idle with nothing '
                    'pending.',
          onTap: ready && settings.canSwitchProvider
              ? () => unawaited(_switchProvider(context))
              : null,
        ),
        if (models.length > 1 || (models.isNotEmpty && model == null))
          AgentChatComposerChip(
            key: const ValueKey<String>('agent-chat-model-chip'),
            label: model?.label ?? session.model ?? 'Default Model',
            tooltip: 'Choose Model',
            onTap: ready
                ? () => unawaited(
                    _pick<String>(context, <PopupMenuEntry<String>>[
                      for (final option in models)
                        AleraDropdownEntry<String>(
                          value: option.id,
                          label: option.label,
                          detail: option.isDefault ? 'Default' : null,
                          selected: option.id == session.model,
                        ),
                    ], (id) => onConfigure(AgentChatConfiguration(model: id))),
                  )
                : null,
          )
        else if (model != null || session.model != null)
          AgentChatComposerChip(
            label: model?.label ?? session.model!,
            tooltip: 'Model',
          ),
        if (runtimeModes.length > 1)
          AgentChatComposerChip(
            key: const ValueKey<String>('agent-chat-runtime-mode-chip'),
            icon: session.runtimeMode == AgentChatRuntimeMode.fullAccess
                ? AleraIcons.warning
                : AleraIcons.secure,
            label: agentChatRuntimeModeLabel(session.runtimeMode),
            highlight: session.runtimeMode == AgentChatRuntimeMode.fullAccess,
            tooltip: 'Choose Approval Mode',
            onTap: ready
                ? () => unawaited(
                    _pick<AgentChatRuntimeMode>(
                      context,
                      <PopupMenuEntry<AgentChatRuntimeMode>>[
                        for (final mode in runtimeModes)
                          AleraDropdownEntry<AgentChatRuntimeMode>(
                            value: mode,
                            label: agentChatRuntimeModeLabel(mode),
                            detail: _runtimeModeDescription(mode),
                            selected: mode == session.runtimeMode,
                          ),
                      ],
                      (mode) => onConfigure(
                        AgentChatConfiguration(runtimeMode: mode),
                      ),
                    ),
                  )
                : null,
          ),
        if (planSupported)
          AgentChatComposerChip(
            key: const ValueKey<String>('agent-chat-plan-toggle'),
            icon: planMode ? AleraIcons.planActive : AleraIcons.plan,
            label: 'Plan',
            highlight: planMode,
            tooltip: planMode ? 'Leave Plan Mode' : 'Plan Before Acting',
            onTap: ready
                ? () => onConfigure(
                    AgentChatConfiguration(
                      interactionMode: planMode
                          ? AgentChatInteractionMode.standard
                          : AgentChatInteractionMode.plan,
                    ),
                  )
                : null,
          ),
      ],
    );
  }

  Future<void> _switchProvider(BuildContext context) async {
    final target = await _pickValue<AgentChatProviderInstance>(
      context,
      <PopupMenuEntry<AgentChatProviderInstance>>[
        for (final candidate in settings.providers)
          AleraDropdownEntry<AgentChatProviderInstance>(
            value: candidate,
            label: candidate.label,
            leading: AgentChatProviderIcon(
              provider: candidate.provider,
              size: AleraTokens.iconLg,
            ),
            detail: candidate.available ? null : candidate.unavailableReason,
            enabled: candidate.available,
            selected: candidate.id == settings.providerInstanceId,
          ),
      ],
    );
    if (target == null ||
        target.id == settings.providerInstanceId ||
        !context.mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Switch to ${target.label}?',
        message:
            '${target.label} continues this chat in a new session. It receives '
            'the earlier messages as context with your next message.',
        confirmLabel: 'Switch Provider',
      ),
    );
    if (confirmed == true) {
      onConfigure(
        AgentChatConfiguration(
          provider: target.provider,
          providerInstanceId: target.id,
        ),
      );
    }
  }
}

Future<void> _pick<T>(
  BuildContext context,
  List<PopupMenuEntry<T>> items,
  ValueChanged<T> onSelected,
) async {
  final value = await _pickValue<T>(context, items);
  if (value != null) onSelected(value);
}

Future<T?> _pickValue<T>(BuildContext context, List<PopupMenuEntry<T>> items) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      origin & box.size,
      Offset.zero & overlay.size,
    ),
    constraints: const BoxConstraints(minWidth: AleraTokens.contextMenuWidth),
    items: items,
  );
}

/// A compact control in the composer footer.
class const AgentChatComposerChip({
  super.key,
  required final String label,
  final String? tooltip,
  final IconData? icon,
  final Widget? leading,
  final bool highlight = false,
  final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? AleraTokens.foreground
        : AleraTokens.foregroundMuted;
    final chip = InkWell(
      onTap: onTap,
      mouseCursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space6,
          vertical: AleraTokens.space4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (leading case final Widget leading) ...<Widget>[
              leading,
              const SizedBox(width: AleraTokens.space4),
            ] else if (icon case final IconData icon) ...<Widget>[
              Icon(icon, size: AleraTokens.iconSm, color: color),
              const SizedBox(width: AleraTokens.space4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: color),
            ),
            if (onTap != null) ...<Widget>[
              const SizedBox(width: AleraTokens.space2),
              Icon(
                AleraIcons.chevronDown,
                size: AleraTokens.iconSm,
                color: AleraTokens.foregroundFaint,
              ),
            ],
          ],
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// How full the provider's context window is, when it reports both ends.
class const AgentChatContextUsage({
  super.key,
  required final AgentChatUsage usage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final fraction = usage.contextFraction;
    if (fraction == null) return const SizedBox.shrink();
    final percent = (fraction * 100).round();
    return Tooltip(
      message:
          'Context $percent% used (${usage.contextTokens} of '
          '${usage.contextWindow} tokens)',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space4),
        child: SizedBox.square(
          dimension: AleraTokens.iconLg,
          child: CircularProgressIndicator(
            value: fraction,
            strokeWidth: AleraTokens.strokeSm,
            backgroundColor: AleraTokens.border,
            color: fraction > 0.9
                ? AleraTokens.warning
                : AleraTokens.foregroundMuted,
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_model_picker.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_settings.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

export 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_model_picker.dart'
    show AgentChatChooseCallback;
export 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_settings.dart';

/// Agent and model, approval mode, plan mode and reasoning effort for the
/// next turn. The picker always shows; on a [compact] composer, which must
/// have a bounded width, the other settings fold into More Composer Controls
/// so Send never scrolls away. That button shows Full Access and Plan Mode
/// while they are on, so folding never hides that the agent acts without
/// asking or only plans, and the model label ellipsizes before it does.
class const AgentChatComposerControls({
  super.key,
  required final AgentChatComposerSettings settings,
  required final bool enabled,
  required final ValueChanged<AgentChatConfiguration> onConfigure,
  required final AgentChatChooseCallback onChoose,
  final bool busy = false,
  final bool compact = false,
  final AleraPopoverController? pickerController,
  final VoidCallback? onRetryCatalog,
  final VoidCallback? onOpenProviderSettings,
}) extends StatelessWidget {
  bool get _ready => enabled && !settings.configuring;

  List<AgentChatRuntimeMode> get _runtimeModes =>
      settings.instance?.runtimeModes ?? const <AgentChatRuntimeMode>[];

  bool get _planSupported =>
      settings.instance?.supportsPlanMode ?? settings.session.capabilities.plan;

  bool get _hasOverflow =>
      _runtimeModes.length > 1 ||
      _planSupported ||
      settings.reasoningEfforts.isNotEmpty;

  bool get _planMode =>
      settings.session.interactionMode == AgentChatInteractionMode.plan;

  bool get _fullAccess =>
      settings.session.runtimeMode == AgentChatRuntimeMode.fullAccess;

  @override
  Widget build(BuildContext context) {
    final session = settings.session;
    final efforts = settings.reasoningEfforts;
    // The runtime restarts the agent for an approval or effort change, which
    // it only accepts between turns.
    final idle = _ready && !busy;
    final picker = AgentChatComposerModelPicker(
      settings: settings,
      enabled: enabled,
      compact: compact,
      controller: pickerController,
      onChoose: onChoose,
      onRetryCatalog: onRetryCatalog,
      onOpenProviderSettings: onOpenProviderSettings,
    );
    if (compact) {
      final states = <String>[
        if (_fullAccess)
          agentChatRuntimeModeLabel(AgentChatRuntimeMode.fullAccess),
        if (_planMode) 'Plan Mode',
      ];
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(child: picker),
          if (_hasOverflow || states.isNotEmpty)
            Builder(
              builder: (context) => _CompactModesButton(
                fullAccess: _fullAccess,
                planMode: _planMode,
                tooltip: <String>[
                  ...states,
                  if (_hasOverflow) 'More Composer Controls',
                ].join(' · '),
                onPressed: _ready && _hasOverflow
                    ? () => unawaited(_openOverflow(context, idle: idle))
                    : null,
              ),
            ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        picker,
        if (_runtimeModes.length > 1)
          AgentChatComposerChip(
            key: const ValueKey<String>('agent-chat-runtime-mode-chip'),
            icon: _fullAccess ? AleraIcons.warning : AleraIcons.secure,
            label: agentChatRuntimeModeLabel(session.runtimeMode),
            highlight: _fullAccess,
            tooltip: idle
                ? 'Choose Approval Mode'
                : 'The approval mode can change once this turn ends.',
            onTap: idle
                ? (context) => unawaited(_chooseRuntimeMode(context))
                : null,
          ),
        if (_planSupported)
          AgentChatComposerChip(
            key: const ValueKey<String>('agent-chat-plan-toggle'),
            icon: _planMode ? AleraIcons.planActive : AleraIcons.plan,
            label: 'Plan',
            highlight: _planMode,
            tooltip: _planMode ? 'Leave Plan Mode' : 'Plan Before Acting',
            onTap: _ready ? (_) => _togglePlan() : null,
          ),
        if (efforts.isNotEmpty)
          AgentChatComposerChip(
            key: const ValueKey<String>('agent-chat-effort-chip'),
            icon: AleraIcons.tune,
            label: switch (settings.reasoningEffort) {
              final String effort => agentChatEffortLabel(effort),
              null => 'Effort',
            },
            tooltip: idle
                ? 'Choose Reasoning Effort'
                : 'The reasoning effort can change once this turn ends.',
            onTap: idle ? (context) => unawaited(_chooseEffort(context)) : null,
          ),
      ],
    );
  }

  void _togglePlan() => onConfigure(
    AgentChatConfiguration(
      interactionMode: _planMode
          ? AgentChatInteractionMode.standard
          : AgentChatInteractionMode.plan,
    ),
  );

  Future<void> _chooseRuntimeMode(BuildContext context) async {
    final mode = await _pickValue<AgentChatRuntimeMode>(
      context,
      _runtimeModeEntries(),
    );
    if (mode != null && context.mounted) {
      await _applyRuntimeMode(context, mode);
    }
  }

  List<PopupMenuEntry<AgentChatRuntimeMode>> _runtimeModeEntries() =>
      <PopupMenuEntry<AgentChatRuntimeMode>>[
        for (final mode in _runtimeModes)
          AleraDropdownEntry<AgentChatRuntimeMode>(
            value: mode,
            label: agentChatRuntimeModeLabel(mode),
            description: agentChatRuntimeModeDescription(mode),
            selected: mode == settings.session.runtimeMode,
          ),
      ];

  /// Full Access lets the agent act without asking, so it is confirmed.
  Future<void> _applyRuntimeMode(
    BuildContext context,
    AgentChatRuntimeMode mode,
  ) async {
    if (mode == settings.session.runtimeMode) return;
    if (mode == AgentChatRuntimeMode.fullAccess) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => const AleraConfirmDialog(
          title: agentChatFullAccessTitle,
          message: agentChatFullAccessMessage,
          confirmLabel: agentChatFullAccessConfirm,
        ),
      );
      if (confirmed != true) return;
    }
    onConfigure(AgentChatConfiguration(runtimeMode: mode));
  }

  Future<void> _chooseEffort(BuildContext context) async {
    final effort = await _pickValue<String>(context, _effortEntries());
    if (effort != null) _applyEffort(effort);
  }

  List<PopupMenuEntry<String>> _effortEntries() => <PopupMenuEntry<String>>[
    for (final effort in settings.reasoningEfforts)
      AleraDropdownEntry<String>(
        value: effort,
        label: agentChatEffortLabel(effort),
        detail: effort == settings.model?.defaultReasoningEffort
            ? 'Default'
            : null,
        selected: effort == settings.reasoningEffort,
      ),
  ];

  void _applyEffort(String effort) {
    if (effort == settings.reasoningEffort) return;
    onConfigure(
      effort == settings.model?.defaultReasoningEffort
          ? const AgentChatConfiguration(resetReasoningEffort: true)
          : AgentChatConfiguration(reasoningEffort: effort),
    );
  }

  Future<void> _openOverflow(BuildContext context, {required bool idle}) async {
    final choice = await _pickValue<_OverflowChoice>(
      context,
      <PopupMenuEntry<_OverflowChoice>>[
        if (_runtimeModes.length > 1)
          for (final mode in _runtimeModes)
            AleraDropdownEntry<_OverflowChoice>(
              value: _RuntimeModeChoice(mode),
              label: agentChatRuntimeModeLabel(mode),
              description: agentChatRuntimeModeDescription(mode),
              selected: mode == settings.session.runtimeMode,
              enabled: idle,
            ),
        if (_planSupported) ...<PopupMenuEntry<_OverflowChoice>>[
          if (_runtimeModes.length > 1) const PopupMenuDivider(),
          AleraDropdownEntry<_OverflowChoice>(
            value: const _PlanChoice(),
            label: 'Plan Mode',
            description: _planMode
                ? 'Leave plan mode with the next message.'
                : 'Plan before acting.',
            selected: _planMode,
          ),
        ],
        if (settings
            .reasoningEfforts
            .isNotEmpty) ...<PopupMenuEntry<_OverflowChoice>>[
          const PopupMenuDivider(),
          for (final effort in settings.reasoningEfforts)
            AleraDropdownEntry<_OverflowChoice>(
              value: _EffortChoice(effort),
              label: 'Effort: ${agentChatEffortLabel(effort)}',
              selected: effort == settings.reasoningEffort,
              enabled: idle,
            ),
        ],
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case _RuntimeModeChoice(:final mode):
        await _applyRuntimeMode(context, mode);
      case _PlanChoice():
        _togglePlan();
      case _EffortChoice(:final effort):
        _applyEffort(effort);
      case null:
        break;
    }
  }
}

sealed class _OverflowChoice {
  const _OverflowChoice();
}

final class _RuntimeModeChoice extends _OverflowChoice {
  const _RuntimeModeChoice(this.mode);

  final AgentChatRuntimeMode mode;

  @override
  bool operator ==(Object other) =>
      other is _RuntimeModeChoice && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

final class _PlanChoice extends _OverflowChoice {
  const _PlanChoice();
}

final class _EffortChoice extends _OverflowChoice {
  const _EffortChoice(this.effort);

  final String effort;

  @override
  bool operator ==(Object other) =>
      other is _EffortChoice && other.effort == effort;

  @override
  int get hashCode => effort.hashCode;
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
    // Bounded so a description wraps under its label instead of squeezing it.
    constraints: const BoxConstraints(
      minWidth: AleraTokens.contextMenuWidth,
      maxWidth: AleraTokens.dialogCompactWidth,
    ),
    items: items,
  );
}

/// A compact control in the composer footer. [onTap] receives the chip's
/// own context so a menu can open beside it.
class const AgentChatComposerChip({
  super.key,
  required final String label,
  final String? tooltip,
  final IconData? icon,
  final Widget? leading,
  final bool highlight = false,
  final ValueChanged<BuildContext>? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? AleraTokens.foreground
        : AleraTokens.foregroundMuted;
    final chip = InkWell(
      onTap: onTap == null ? null : () => onTap!(context),
      mouseCursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
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

/// More Composer Controls on a compact composer. Its icon is the state of
/// the folded settings, Full Access and Plan Mode, while either is on, so the
/// button tells the truth about the next turn without a label.
class const _CompactModesButton({
  required final bool fullAccess,
  required final bool planMode,
  required final String tooltip,
  required final VoidCallback? onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: HoverContainer(
        key: const ValueKey<String>('agent-chat-more-controls'),
        onTap: onPressed,
        borderRadius: AleraTokens.radiusSm,
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AleraTokens.iconButtonSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: AleraTokens.space4,
            children: <Widget>[
              if (fullAccess)
                const Icon(
                  AleraIcons.warning,
                  key: ValueKey<String>('agent-chat-full-access-indicator'),
                  size: AleraTokens.iconSm,
                  color: AleraTokens.warning,
                ),
              if (planMode)
                const Icon(
                  AleraIcons.planActive,
                  key: ValueKey<String>('agent-chat-plan-indicator'),
                  size: AleraTokens.iconSm,
                  color: AleraTokens.foreground,
                ),
              if (!fullAccess && !planMode)
                const Icon(
                  AleraIcons.tune,
                  size: AleraTokens.iconSm,
                  color: AleraTokens.foregroundMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

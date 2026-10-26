import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_shortcut_targets.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_queued_edit.dart';
import 'package:alera/src/features/keyboard/application/keybinding_resolver.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The effort one step up ([delta] 1) or down (-1) from the current one, as
/// the configuration that applies it; `null` at either end or without
/// efforts. The model's default effort is applied as a reset.
AgentChatConfiguration? agentChatSteppedEffort(
  AgentChatComposerSettings settings,
  int delta,
) {
  final efforts = settings.reasoningEfforts;
  if (efforts.isEmpty) return null;
  final current = efforts.indexOf(settings.reasoningEffort ?? '');
  final next = current < 0
      ? (delta > 0 ? 0 : efforts.length - 1)
      : current + delta;
  if (next < 0 || next >= efforts.length || next == current) return null;
  final effort = efforts[next];
  return effort == settings.model?.defaultReasoningEffort
      ? const AgentChatConfiguration(resetReasoningEffort: true)
      : AgentChatConfiguration(reasoningEffort: effort);
}

/// The interaction mode after the current one: standard and plan where the
/// agent plans, else `null`.
AgentChatConfiguration? agentChatNextMode(AgentChatComposerSettings settings) {
  if (!agentChatPlanModeSupported(settings)) return null;
  return AgentChatConfiguration(
    interactionMode:
        settings.session.interactionMode == AgentChatInteractionMode.plan
        ? AgentChatInteractionMode.standard
        : AgentChatInteractionMode.plan,
  );
}

/// The first chord bound to [id] for this platform, formatted for a keycap,
/// or `null` when the action has none.
String? agentChatShortcutLabel(WidgetRef ref, KeyboardActionId id) {
  final resolver = KeybindingResolver(
    settings: ref.watch(settingsControllerProvider).keyboard,
  );
  final chord = resolver.effectiveChords(id).firstOrNull;
  return chord?.format(isMacOS: resolver.platform.isMacOS);
}

/// Takes the chat keyboard actions for one chat while the keyboard focus is
/// in the chat. The workbench pane or panel showing the chat is a
/// [FocusScope] (see AGENTS.md), so focus inside that scope is focus in this
/// chat. A shortcut that cannot act right now reports so, and the key goes
/// on to the focused field. Draws nothing.
class const AgentChatShortcutTarget({
  super.key,
  required final String chatId,
  required final String workspaceId,
  final AgentChatQueuedEdit? queuedEdit,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatShortcutTarget> createState() =>
      _AgentChatShortcutTargetState();
}

class _AgentChatShortcutTargetState
    extends ConsumerState<AgentChatShortcutTarget> {
  late final AgentChatShortcutTargets _targets;

  @override
  void initState() {
    super.initState();
    _targets = ref.read(agentChatShortcutTargetsProvider)..register(_handle);
  }

  @override
  void dispose() {
    _targets.unregister(_handle);
    super.dispose();
  }

  AgentChatControllerProvider get _provider =>
      agentChatControllerProvider(widget.chatId, widget.workspaceId);

  bool _supports(String capability) =>
      ref.read(agentChatCapabilityProvider(capability)).value ?? false;

  bool _handle(AgentChatShortcut shortcut) {
    if (!mounted || !FocusScope.of(context).hasFocus) return false;
    final state = ref.read(_provider);
    final thread = state.thread;
    if (thread == null) return false;
    final controller = ref.read(_provider.notifier);
    final queue = thread.queue;
    switch (shortcut) {
      case AgentChatShortcut.stop:
        if (!state.canInterrupt || state.interrupting) return false;
        unawaited(controller.interrupt());
      case AgentChatShortcut.steerNextQueued:
        if (queue.isEmpty ||
            !state.canSteer ||
            !_supports(AgentChatWire.queueSteerCapability)) {
          return false;
        }
        unawaited(controller.steerQueued(queue.first.queueId));
      case AgentChatShortcut.editLastQueued:
        return _editLast(queue);
      case AgentChatShortcut.increaseEffort:
      case AgentChatShortcut.decreaseEffort:
      case AgentChatShortcut.cycleMode:
        final settings = _settings(state);
        // The runtime takes effort changes only between turns.
        final configuration = switch (shortcut) {
          AgentChatShortcut.cycleMode => agentChatNextMode(settings),
          _ when state.busy => null,
          AgentChatShortcut.increaseEffort => agentChatSteppedEffort(
            settings,
            1,
          ),
          _ => agentChatSteppedEffort(settings, -1),
        };
        if (configuration == null || !state.canSend || state.configuring) {
          return false;
        }
        unawaited(controller.configure(configuration));
    }
    return true;
  }

  /// Like the arrow recall of earlier prompts, only from the start of the
  /// composer, so Alt+Up keeps moving the caret anywhere else.
  bool _editLast(List<AgentChatQueueEntry> queue) {
    final edit = widget.queuedEdit;
    if (edit == null) return false;
    final field = edit.composer;
    final selection = field.textController.selection;
    if (queue.isEmpty ||
        edit.isEditing ||
        !field.focusNode.hasFocus ||
        (field.textController.text.isNotEmpty &&
            !(selection.isCollapsed && selection.baseOffset == 0)) ||
        !_supports(AgentChatWire.queueEditCapability)) {
      return false;
    }
    edit.begin(queue.last);
    return true;
  }

  AgentChatComposerSettings _settings(AgentChatViewState state) {
    final thread = state.thread!;
    return AgentChatComposerSettings(
      provider: thread.provider,
      providerInstanceId: thread.providerInstanceId,
      session: thread.session,
      providers:
          ref
              .read(agentChatProviderCatalogProvider(widget.workspaceId))
              .value ??
          const <AgentChatProviderInstance>[],
      canSwitchProvider: state.canSwitchProvider,
      configuring: state.configuring,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

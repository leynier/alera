import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_agent_runner.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_errors.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/text_actions/application/text_action_prompt.dart';
import 'package:alera/src/features/text_actions/application/text_action_replacement.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TextActionsScope extends ConsumerStatefulWidget {
  const TextActionsScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TextActionsScope> createState() => _TextActionsScopeState();
}

class _TextActionsScopeState extends ConsumerState<TextActionsScope> {
  final Set<Object> _runningTargets = <Object>{};
  var _runSequence = 0;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final activeWorkspacePath = ref.watch(
      workbenchControllerProvider.select(
        (state) => state.activeWorkspace?.path,
      ),
    );
    final enabled =
        _desktopPlatform &&
        settings.aiAssist.enabled &&
        settings.textActions.enabledActions.isNotEmpty;
    return AleraTextActionsScope(
      enabled: enabled,
      actions: <AleraTextActionMenuItem>[
        for (final action in settings.textActions.enabledActions)
          AleraTextActionMenuItem(id: action.id, label: action.name),
      ],
      onOpen: (context, target, globalAnchor) =>
          _openMenu(context, target, globalAnchor, activeWorkspacePath),
      onRun: (target, actionId) =>
          unawaited(_runAction(target, actionId, activeWorkspacePath)),
      child: widget.child,
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    AleraTextActionTarget target,
    Offset globalAnchor,
    String? activeWorkspacePath,
  ) async {
    if (_runningTargets.contains(target.identity)) {
      return;
    }
    final settings = ref.read(settingsControllerProvider);
    final actions = settings.textActions.enabledActions;
    if (!settings.aiAssist.enabled || actions.isEmpty) {
      return;
    }
    final overlay = Navigator.of(context).overlay;
    if (overlay == null || !context.mounted) {
      return;
    }
    final overlayBox = overlay.context.findRenderObject();
    if (overlayBox is! RenderBox) {
      return;
    }
    final anchor = overlayBox.globalToLocal(globalAnchor);
    final position = RelativeRect.fromLTRB(
      anchor.dx,
      anchor.dy,
      overlayBox.size.width - anchor.dx,
      overlayBox.size.height - anchor.dy,
    );
    final selectedAction = await showMenu<TextAction>(
      context: context,
      position: position,
      color: AleraTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        side: const BorderSide(color: AleraTokens.border),
      ),
      items: <PopupMenuEntry<TextAction>>[
        for (final action in actions)
          AleraDropdownEntry<TextAction>(value: action, label: action.name),
      ],
    );
    if (selectedAction == null || !mounted) {
      return;
    }
    unawaited(_runAction(target, selectedAction.id, activeWorkspacePath));
  }

  Future<void> _runAction(
    AleraTextActionTarget target,
    String actionId,
    String? activeWorkspacePath,
  ) async {
    if (!target.isAvailable() || _runningTargets.contains(target.identity)) {
      return;
    }
    final captured = target.readValue();
    final selection = captured.selection;
    if (!selection.isValid ||
        selection.isCollapsed ||
        selection.start < 0 ||
        selection.end > captured.text.length) {
      return;
    }
    final selectedText = captured.text.substring(
      selection.start,
      selection.end,
    );
    if (selectedText.isEmpty) {
      return;
    }
    final settings = ref.read(settingsControllerProvider);
    final action = settings.textActions.actions
        .where((candidate) => candidate.id == actionId && candidate.enabled)
        .firstOrNull;
    if (action == null) {
      return;
    }
    _runningTargets.add(target.identity);
    final runId = 'text-action-${++_runSequence}';
    AleraToast.publish(message: 'Running ${action.name}.');
    try {
      final currentSettings = ref.read(settingsControllerProvider);
      final currentAction = currentSettings.textActions.actions
          .where((candidate) => candidate.id == action.id)
          .firstOrNull;
      if (currentAction == null || !currentAction.enabled) {
        return;
      }
      final agent = currentAction.effectiveAgent(currentSettings.aiAssist);
      final model = currentAction.effectiveModel(currentSettings.aiAssist);
      final reasoning = currentAction.reasoningFor(
        currentSettings.aiAssist,
        model: model,
      );
      final result = await ref
          .read(aiAssistAgentRunnerProvider)
          .run(
            AiAssistAgentRunRequest(
              settings: currentSettings.aiAssist,
              prompt: buildTextActionPrompt(
                instruction: currentAction.prompt,
                selectedText: selectedText,
              ),
              runId: runId,
              workingDirectory: activeWorkspacePath,
              agent: agent,
              model: model,
              reasoning: reasoning,
            ),
          );
      if (!mounted || !target.isAvailable()) {
        return;
      }
      final currentValue = target.readValue();
      if (currentValue != captured) {
        AleraToast.publish(
          message: 'Text changed while the action was running.',
        );
        return;
      }
      if (!canApplyTextActionReplacement(
        captured: captured,
        current: currentValue,
        replacement: result.text,
      )) {
        AleraToast.publish(
          message: 'Text action returned no replacement text.',
          tone: AleraToastTone.error,
        );
        return;
      }
      if (!target.applyReplacement(captured, result.text)) {
        AleraToast.publish(
          message: 'Text action could not update this field.',
          tone: AleraToastTone.error,
        );
        return;
      }
      AleraToast.publish(
        message: 'Text action applied.',
        tone: AleraToastTone.success,
      );
    } on AiAssistCanceledException {
      AleraToast.publish(message: 'Text action was canceled.');
    } on AiAssistException catch (error) {
      AleraToast.publish(
        message: 'Text action failed: ${error.message}',
        tone: AleraToastTone.error,
      );
    } on Object catch (error) {
      AleraToast.publish(
        message: 'Text action failed: $error',
        tone: AleraToastTone.error,
      );
    } finally {
      _runningTargets.remove(target.identity);
    }
  }
}

bool get _desktopPlatform {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };
}

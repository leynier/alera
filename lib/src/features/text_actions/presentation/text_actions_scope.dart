import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_agent_runner.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_errors.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_providers.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/text_actions/application/text_action_prompt.dart';
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
  final Set<EditableTextState> _runningFields = <EditableTextState>{};
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
        settings.aiTextGeneration.enabled &&
        settings.textActions.enabledActions.isNotEmpty;
    return AleraTextActionsScope(
      enabled: enabled,
      onOpen: (context, editableTextState) =>
          _openMenu(context, editableTextState, activeWorkspacePath),
      child: widget.child,
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    EditableTextState editableTextState,
    String? activeWorkspacePath,
  ) async {
    if (_runningFields.contains(editableTextState)) {
      return;
    }
    final settings = ref.read(settingsControllerProvider);
    final actions = settings.textActions.enabledActions;
    if (!settings.aiTextGeneration.enabled || actions.isEmpty) {
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
    final anchors = editableTextState.contextMenuAnchors;
    final globalAnchor = anchors.secondaryAnchor ?? anchors.primaryAnchor;
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
    unawaited(
      _runAction(editableTextState, selectedAction, activeWorkspacePath),
    );
  }

  Future<void> _runAction(
    EditableTextState editableTextState,
    TextAction action,
    String? activeWorkspacePath,
  ) async {
    if (!editableTextState.mounted ||
        _runningFields.contains(editableTextState)) {
      return;
    }
    final captured = editableTextState.textEditingValue;
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
    _runningFields.add(editableTextState);
    final runId = 'text-action-${++_runSequence}';
    AleraToast.publish(message: 'Running ${action.name}.');
    try {
      final settings = ref.read(settingsControllerProvider);
      final currentAction = settings.textActions.actions
          .where((candidate) => candidate.id == action.id)
          .firstOrNull;
      if (currentAction == null || !currentAction.enabled) {
        return;
      }
      final agent = currentAction.effectiveAgent(settings.aiTextGeneration);
      final model = currentAction.effectiveModel(settings.aiTextGeneration);
      final reasoning = currentAction.reasoningFor(
        settings.aiTextGeneration,
        model: model,
      );
      final result = await ref
          .read(aiTextAgentRunnerProvider)
          .run(
            AiTextAgentRunRequest(
              settings: settings.aiTextGeneration,
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
      if (!mounted || !editableTextState.mounted) {
        return;
      }
      if (editableTextState.textEditingValue != captured) {
        AleraToast.publish(
          message: 'Text changed while the action was running.',
        );
        return;
      }
      if (result.text.trim().isEmpty) {
        AleraToast.publish(
          message: 'Text action returned no replacement text.',
          tone: AleraToastTone.error,
        );
        return;
      }
      Actions.invoke(
        editableTextState.context,
        ReplaceTextIntent(
          captured,
          result.text,
          captured.selection,
          SelectionChangedCause.toolbar,
        ),
      );
      AleraToast.publish(
        message: 'Text action applied.',
        tone: AleraToastTone.success,
      );
    } on AiTextGenerationCanceledException {
      AleraToast.publish(message: 'Text action was canceled.');
    } on AiTextGenerationException catch (error) {
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
      _runningFields.remove(editableTextState);
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

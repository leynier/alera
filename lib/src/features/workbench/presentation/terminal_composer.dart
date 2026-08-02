import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_composer.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';

class TerminalComposer extends StatelessWidget {
  const TerminalComposer({super.key, required this.session});

  final TerminalSessionHandle session;

  @override
  Widget build(BuildContext context) {
    final composer = session.composerController;
    final textActionsScope = AleraTextActionsScope.maybeOf(context);
    return AleraComposer(
      controller: composer.textController,
      focusNode: composer.focusNode,
      enabled: !composer.submitting,
      textActions: textActionsScope?.enabled == true
          ? textActionsScope!.actions
          : const [],
      onTextActionSelected: (actionId) {
        final focusContext = composer.focusNode.context;
        final editableTextState = focusContext
            ?.findAncestorStateOfType<EditableTextState>();
        if (editableTextState != null) {
          textActionsScope?.run(editableTextState, actionId);
        }
      },
      onSend: () => unawaited(_send(context)),
      onClose: composer.hide,
    );
  }

  Future<void> _send(BuildContext context) async {
    final composer = session.composerController;
    final prompt = composer.textController.text;
    if (composer.submitting || prompt.trim().isEmpty) {
      return;
    }
    composer.setSubmitting(true);
    try {
      final submitted = await session.submitText(prompt);
      if (!submitted) {
        AleraToast.publish(
          message: 'The terminal could not accept the prompt.',
          tone: AleraToastTone.error,
        );
        return;
      }
      if (context.mounted && composer.textController.text == prompt) {
        composer.textController.clear();
        composer.focusNode.requestFocus();
      }
    } on Object catch (error) {
      AleraToast.publish(
        message: 'The terminal could not accept the prompt: $error',
        tone: AleraToastTone.error,
      );
    } finally {
      composer.setSubmitting(false);
    }
  }
}

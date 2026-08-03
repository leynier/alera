import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_composer.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/features/workbench/domain/terminal_image_paste.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';

class TerminalComposer extends StatelessWidget {
  const TerminalComposer({
    super.key,
    required this.session,
    this.clipboard = const NativeTerminalClipboard(),
  });

  final TerminalSessionHandle session;
  final TerminalClipboard clipboard;

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
      onPaste: _pasteClipboard,
      onSend: () => unawaited(_send(context)),
      onClose: composer.hide,
    );
  }

  Future<bool> _pasteClipboard() async {
    String? clipboardText;
    try {
      clipboardText = await clipboard.readText();
    } catch (_) {
      // Image-only clipboards can reject text reads on some platforms.
    }
    if (clipboardText != null && clipboardText.isNotEmpty) {
      return false;
    }
    try {
      final imagePath = await clipboard.saveImageAsTempFile();
      if (imagePath == null || imagePath.isEmpty) {
        return false;
      }
      final composer = session.composerController;
      final focusContext = composer.focusNode.context;
      if (focusContext == null || !focusContext.mounted) {
        return true;
      }
      final value = composer.textController.value;
      final selection = _validSelection(value);
      composer.textController.value = value.replaced(
        selection,
        sanitizeTerminalImagePastePath(imagePath),
      );
      composer.focusNode.requestFocus();
      return true;
    } catch (_) {
      AleraToast.publish(
        message: 'Could not paste clipboard image.',
        tone: AleraToastTone.error,
      );
      return true;
    }
  }

  TextSelection _validSelection(TextEditingValue value) {
    final selection = value.selection;
    if (selection.isValid &&
        selection.start <= value.text.length &&
        selection.end <= value.text.length) {
      return selection;
    }
    return TextSelection.collapsed(offset: value.text.length);
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

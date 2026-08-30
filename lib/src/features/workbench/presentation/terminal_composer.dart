import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_composer.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_submission.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_attachment_bar.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:flutter/material.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_control.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_target.dart';

class const TerminalComposer({
  super.key,
  required final TerminalSessionHandle session,
  final TerminalClipboard clipboard = const NativeTerminalClipboard(),
  final ExternalUriLauncher? externalUriLauncher,
  final Future<bool> Function(String path)? onOpenWorkspaceFile,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final composer = session.composerController;
    final textActionsScope = AleraTextActionsScope.maybeOf(context);
    return AiDictationTarget(
      controller: composer.textController,
      focusNode: composer.focusNode,
      workspaceId: session.workspaceId,
      tabId: session.tabId,
      builder: (context, targetId) => AnimatedBuilder(
        animation: composer,
        builder: (context, _) => AleraComposer(
          controller: composer.textController,
          focusNode: composer.focusNode,
          enabled: !composer.submitting,
          hasAttachments: composer.attachments.isNotEmpty,
          attachmentBar: TerminalComposerAttachmentBar(
            attachments: composer.attachments,
            onRemove: composer.removeAttachment,
            onOpenFile: (path) => unawaited(_openFile(path)),
            enabled: !composer.submitting,
          ),
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
          trailingAction: AiDictationControl(
            key: const ValueKey<String>('terminal-composer-dictation-control'),
            targetId: targetId,
          ),
          onSend: () => unawaited(_send(context)),
          onClose: composer.hide,
        ),
      ),
    );
  }

  Future<bool> _pasteClipboard() async {
    try {
      final filePaths = await clipboard.readFilePaths();
      if (filePaths.isNotEmpty) {
        final composer = session.composerController;
        composer.addPathAttachments(filePaths);
        composer.focusNode.requestFocus();
        return true;
      }
    } catch (_) {
      // Fall through to text and image clipboard formats.
    }
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
      composer.addPathAttachment(imagePath, kind: .image);
      composer.focusNode.requestFocus();
      return true;
    } catch (_) {
      AleraToast.publish(
        message: 'Could not paste clipboard image.',
        tone: .error,
      );
      return true;
    }
  }

  Future<void> _openFile(String path) async {
    try {
      if (await onOpenWorkspaceFile?.call(path) == true) {
        return;
      }
      await (externalUriLauncher ?? UrlLauncherExternalUriLauncher()).open(
        .file(path),
      );
    } on Object catch (error) {
      AleraToast.publish(
        message: 'Could not open attached file: $error',
        tone: .error,
      );
    }
  }

  Future<void> _send(BuildContext context) async {
    final composer = session.composerController;
    final prompt = composer.textController.text;
    final attachments = composer.attachments;
    if (composer.submitting || (prompt.trim().isEmpty && attachments.isEmpty)) {
      return;
    }
    final submission = buildTerminalComposerSubmission(
      prompt: prompt,
      attachments: attachments,
      workspacePath: session.workspacePath,
    );
    composer.setSubmitting(true);
    try {
      final submitted = await session.submitText(submission);
      if (!submitted) {
        AleraToast.publish(
          message: 'The terminal could not accept the prompt.',
          tone: .error,
        );
        return;
      }
      if (composer.textController.text == prompt) {
        composer.textController.clear();
      }
      composer.removeAttachments(
        attachments.map((attachment) => attachment.id),
      );
      if (context.mounted) {
        composer.focusNode.requestFocus();
      }
    } on Object catch (error) {
      AleraToast.publish(
        message: 'The terminal could not accept the prompt: $error',
        tone: .error,
      );
    } finally {
      composer.setSubmitting(false);
    }
  }
}

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_attachment_upload_bar.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_control.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_review_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

double agentChatComposerMinimumInputHeight(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: ' ', style: Theme.of(context).textTheme.bodyLarge),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final lineHeight = painter.preferredLineHeight;
  painter.dispose();
  // Flutter centers an oversized caret when its line equals the viewport;
  // leave a small margin so the normal reveal path can scroll it into view.
  return lineHeight +
      AleraTokens.space12 +
      AleraTokens.space4 +
      AleraTokens.space2;
}

double agentChatComposerMinimumHeight(BuildContext context) =>
    agentChatComposerMinimumInputHeight(context) +
    AleraTokens.minTapTarget +
    AleraTokens.space4 +
    AleraTokens.space4 +
    AleraTokens.space8 +
    MediaQuery.paddingOf(context).bottom;

/// The prompt field of a chat. Send stays available while a turn runs: the
/// runtime queues the message behind it, so the person never has to wait to
/// write the next instruction. Where the agent takes input mid-turn, a long
/// press on Send steers the running turn instead. Stop sits next to it while
/// there is a turn. While a picked attachment uploads, Send and Add
/// Attachment wait for it and the text stays editable.
class const AgentChatComposer({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final String chatId,
  required final TextEditingController controller,
  required final FocusNode focusNode,
  required final List<AgentChatDraftAttachment> attachments,
  required final bool enabled,
  required final String hintText,
  final bool sendBlocked = false,
  required final bool turnActive,
  required final bool canInterrupt,
  required final bool interrupting,
  required final VoidCallback? onAttach,
  required final ValueListenable<AgentChatAttachmentUploadStatus?> upload,
  required final VoidCallback onDismissUpload,
  required final ValueChanged<AgentChatDraftAttachment> onRemoveAttachment,
  required final VoidCallback onSend,
  required final VoidCallback onStop,
  final VoidCallback? onSteer,
  final Widget? settings,

  /// The `@` and `/` suggestions, drawn above the box while they are open.
  final Widget? suggestions,

  /// What Send does instead of sending or queueing, such as declining a
  /// pending approval.
  final String? sendLabel,

  /// A strip above the field, such as the banner of a queued message being
  /// edited.
  final Widget? header,
}) extends StatelessWidget {
  String get _dictationTarget => 'agent-chat-$chatId';

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space12,
        AleraTokens.space4,
        AleraTokens.space12,
        AleraTokens.space8,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: .min,
          children: <Widget>[
            MobileAiDictationReviewBar(
              hostId: hostId,
              targetKey: _dictationTarget,
            ),
            ValueListenableBuilder<AgentChatAttachmentUploadStatus?>(
              valueListenable: upload,
              builder: (context, status, _) => status == null
                  ? const SizedBox.shrink()
                  : AgentChatAttachmentUploadBar(
                      status: status,
                      // The picked file is gone, so Retry picks again.
                      onRetry: enabled ? onAttach : null,
                      onDismiss: onDismissUpload,
                    ),
            ),
            // Only what the box can spare: a keyboard that leaves little room
            // squeezes the suggestions, never the input, and hides them when
            // not even a header and one row fit.
            if (suggestions case final suggestions?)
              if (constraints.maxHeight -
                      agentChatComposerMinimumHeight(context)
                  case final room when room >= AleraTokens.minTapTarget * 2)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: room),
                  child: suggestions,
                ),
            Flexible(
              fit: .loose,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AleraTokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
                  border: Border.all(color: AleraTokens.border),
                ),
                child: Column(
                  mainAxisSize: .min,
                  children: <Widget>[
                    ?header,
                    Flexible(
                      fit: .loose,
                      child: LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          primary: false,
                          child: Column(
                            mainAxisSize: .min,
                            children: <Widget>[
                              if (attachments.isNotEmpty)
                                _AttachmentChips(
                                  attachments: attachments,
                                  onRemove: enabled ? onRemoveAttachment : null,
                                ),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  // RenderEditable needs one full scaled line
                                  // to scroll its caret into view.
                                  minHeight:
                                      agentChatComposerMinimumInputHeight(
                                        context,
                                      ).clamp(0.0, constraints.maxHeight),
                                  maxHeight: constraints.maxHeight,
                                ),
                                child: TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  enabled: enabled,
                                  minLines: 1,
                                  maxLines: AleraTokens.composeBarMaxLines,
                                  textInputAction: .newline,
                                  keyboardType: .multiline,
                                  decoration: InputDecoration(
                                    border: .none,
                                    enabledBorder: .none,
                                    focusedBorder: .none,
                                    disabledBorder: .none,
                                    filled: false,
                                    contentPadding: const EdgeInsets.fromLTRB(
                                      AleraTokens.space16,
                                      AleraTokens.space12,
                                      AleraTokens.space16,
                                      AleraTokens.space4,
                                    ),
                                    hintText: hintText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AleraTokens.space4,
                        0,
                        AleraTokens.space4,
                        AleraTokens.space4,
                      ),
                      child: Row(
                        children: <Widget>[
                          MobileAiDictationControl(
                            hostId: hostId,
                            targetKey: _dictationTarget,
                            controller: controller,
                            workspaceId: workspaceId,
                            enabled: enabled,
                          ),
                          if (onAttach != null)
                            ValueListenableBuilder<
                              AgentChatAttachmentUploadStatus?
                            >(
                              valueListenable: upload,
                              builder: (context, status, _) => IconButton(
                                tooltip: 'Add Attachment',
                                onPressed:
                                    enabled &&
                                        status is! AgentChatAttachmentUploading
                                    ? onAttach
                                    : null,
                                icon: const Icon(AleraIcons.attach),
                              ),
                            ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: settings ?? const SizedBox.shrink(),
                            ),
                          ),
                          if (turnActive && canInterrupt)
                            IconButton(
                              tooltip: 'Stop',
                              onPressed: enabled && !interrupting
                                  ? onStop
                                  : null,
                              icon: interrupting
                                  ? const SizedBox.square(
                                      dimension: AleraTokens.space16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: AleraTokens.strokeSm,
                                      ),
                                    )
                                  : const Icon(AleraIcons.stop),
                            ),
                          ListenableBuilder(
                            listenable: Listenable.merge(<Listenable>[
                              controller,
                              upload,
                            ]),
                            builder: (context, _) {
                              // Typing stays open while the agent cannot run or
                              // a file uploads, so the draft is ready once it
                              // can go.
                              final ready =
                                  enabled &&
                                  !sendBlocked &&
                                  upload.value
                                      is! AgentChatAttachmentUploading &&
                                  (controller.text.trim().isNotEmpty ||
                                      attachments.isNotEmpty);
                              final steer = turnActive ? onSteer : null;
                              final button = IconButton.filled(
                                // A tooltip would take the long press Steer
                                // needs, so the hint moves to semantics.
                                tooltip: steer != null
                                    ? null
                                    : sendLabel ??
                                          (turnActive
                                              ? 'Queue Message'
                                              : 'Send'),
                                onPressed: ready ? onSend : null,
                                icon: Icon(
                                  turnActive
                                      ? AleraIcons.queuedMessage
                                      : AleraIcons.send,
                                ),
                              );
                              if (steer == null) return button;
                              return Semantics(
                                label: sendLabel ?? 'Queue Message',
                                onLongPressHint: 'Steer the running turn',
                                child: GestureDetector(
                                  onLongPress: ready ? steer : null,
                                  child: button,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class const _AttachmentChips({
  required final List<AgentChatDraftAttachment> attachments,
  required final ValueChanged<AgentChatDraftAttachment>? onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AleraTokens.space12,
      AleraTokens.space8,
      AleraTokens.space12,
      0,
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: AleraTokens.space6,
        runSpacing: AleraTokens.space6,
        children: <Widget>[
          for (final attachment in attachments)
            InputChip(
              avatar: Icon(
                attachment.isImage ? AleraIcons.viewImage : AleraIcons.file,
                size: AleraTokens.iconSm,
              ),
              label: Text(attachment.displayName, overflow: .ellipsis),
              onDeleted: onRemove == null ? null : () => onRemove!(attachment),
              deleteButtonTooltipMessage: 'Remove Attachment',
            ),
        ],
      ),
    ),
  );
}

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_control.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_review_bar.dart';
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
/// write the next instruction. Stop sits next to it while there is a turn.
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
  required final bool turnActive,
  required final bool canInterrupt,
  required final bool interrupting,
  required final VoidCallback? onAttach,
  required final ValueChanged<AgentChatDraftAttachment> onRemoveAttachment,
  required final VoidCallback onSend,
  required final VoidCallback onStop,
  final Widget? settings,
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
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          MobileAiDictationReviewBar(
            hostId: hostId,
            targetKey: _dictationTarget,
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
                                minHeight: agentChatComposerMinimumInputHeight(
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
                          IconButton(
                            tooltip: 'Add Attachment',
                            onPressed: enabled ? onAttach : null,
                            icon: const Icon(AleraIcons.attach),
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
                            onPressed: enabled && !interrupting ? onStop : null,
                            icon: interrupting
                                ? const SizedBox.square(
                                    dimension: AleraTokens.space16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: AleraTokens.strokeSm,
                                    ),
                                  )
                                : const Icon(AleraIcons.stop),
                          ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: controller,
                          builder: (context, value, _) {
                            final ready =
                                enabled &&
                                (value.text.trim().isNotEmpty ||
                                    attachments.isNotEmpty);
                            return IconButton.filled(
                              tooltip: turnActive ? 'Queue Message' : 'Send',
                              onPressed: ready ? onSend : null,
                              icon: Icon(
                                turnActive
                                    ? AleraIcons.queuedMessage
                                    : AleraIcons.send,
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

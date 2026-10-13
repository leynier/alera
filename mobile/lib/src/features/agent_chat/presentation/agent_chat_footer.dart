import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/chat/alera_message_queue.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_question_card.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_card.dart';
import 'package:flutter/material.dart';

/// What sits between the transcript and the composer: the question the agent
/// is blocked on, and the messages the runtime holds for after this turn.
/// The docks scroll within half the available height. The composer pins its
/// actions while its input shrinks for a keyboard or large text.
class const AgentChatFooter({
  super.key,
  required final List<AgentChatRequest> questions,
  required final List<AgentChatQueueEntry> queue,
  required final bool canRespond,
  required final Set<String> respondingRequestIds,
  required final AgentChatRespond onRespond,
  required final Future<void> Function(AgentChatQueueEntry entry)
  onRemoveQueued,
  required final Future<void> Function(AgentChatQueueEntry entry) onEditQueued,
  required final Widget composer,
  required final double minimumComposerHeight,
  final List<Widget> notices = const <Widget>[],
  final Widget? tasks,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final question = questions.firstOrNull;
    final upper = <Widget>[
      ...notices,
      if (question != null)
        AgentChatQuestionCard(
          key: ValueKey<String>('question-${question.id}'),
          request: question,
          enabled: canRespond && !respondingRequestIds.contains(question.id),
          onRespond: onRespond,
        ),
      if (queue.isNotEmpty)
        AleraMessageQueue(
          messages: <AleraQueuedMessageRow>[
            for (final entry in queue)
              AleraQueuedMessageRow(
                id: entry.queueId,
                text: entry.text,
                attachmentCount: entry.attachments.length,
                hasImage: entry.attachments.any(
                  (attachment) => attachment.type.isImage,
                ),
              ),
          ],
          // Steering a queued message would be two requests that can half
          // fail; Edit and Remove are what the runtime offers atomically.
          canSteer: false,
          onSteer: (_) async {},
          onRemove: (id) => _withEntry(id, onRemoveQueued),
          onEdit: (id) => _withEntry(id, onEditQueued),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final dockReservation = (constraints.maxHeight - minimumComposerHeight)
            .clamp(0.0, AleraTokens.minTapTarget);
        return Column(
          mainAxisSize: .min,
          children: <Widget>[
            if (tasks != null || upper.isNotEmpty)
              Flexible(
                fit: .loose,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight / 2,
                  ),
                  child: SingleChildScrollView(
                    primary: false,
                    padding: EdgeInsets.fromLTRB(
                      AleraTokens.space12,
                      upper.isEmpty ? 0 : AleraTokens.space4,
                      AleraTokens.space12,
                      0,
                    ),
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .stretch,
                      children: <Widget>[
                        ?tasks,
                        Column(
                          mainAxisSize: .min,
                          crossAxisAlignment: .stretch,
                          spacing: AleraTokens.space8,
                          children: upper,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                // A full scaled input line and its controls take priority;
                // notices and questions use the remaining scrollable space.
                maxHeight:
                    (constraints.maxHeight -
                            (tasks == null && upper.isEmpty
                                ? 0
                                : dockReservation))
                        .clamp(0.0, constraints.maxHeight),
              ),
              child: composer,
            ),
          ],
        );
      },
    );
  }

  Future<void> _withEntry(
    String queueId,
    Future<void> Function(AgentChatQueueEntry entry) action,
  ) async {
    for (final entry in queue) {
      if (entry.queueId == queueId) return action(entry);
    }
  }
}

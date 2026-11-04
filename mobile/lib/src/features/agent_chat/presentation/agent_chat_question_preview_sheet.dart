import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:flutter/material.dart';

/// The Markdown an agent attached to one answer option, as a bottom sheet,
/// so reading it never answers the question.
Future<void> showAgentChatQuestionPreview(
  BuildContext context,
  AgentChatQuestionOption option,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: AleraTokens.pagePadding,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: AleraTokens.space8,
          children: <Widget>[
            Text(option.label, style: Theme.of(context).textTheme.titleMedium),
            AgentChatMarkdown(text: option.preview ?? ''),
          ],
        ),
      ),
    ),
  ),
);

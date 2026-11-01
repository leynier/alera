import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:flutter/material.dart';

/// The Markdown an agent attached to one answer option, such as the code an
/// approach would write. Collapsed by default, so the card keeps its height
/// and number shortcuts, and opening it never answers the question.
class const AgentChatQuestionOptionPreview({
  super.key,
  required final String preview,
}) extends StatefulWidget {
  @override
  State<AgentChatQuestionOptionPreview> createState() =>
      _AgentChatQuestionOptionPreviewState();
}

class _AgentChatQuestionOptionPreviewState
    extends State<AgentChatQuestionOptionPreview> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    children: <Widget>[
      TextButton.icon(
        key: const ValueKey<String>('agent-chat-question-preview-toggle'),
        onPressed: () => setState(() => _open = !_open),
        icon: const Icon(AleraIcons.preview, size: AleraTokens.iconSm),
        label: Text(_open ? 'Hide Preview' : 'Show Preview'),
      ),
      if (_open)
        Container(
          constraints: const BoxConstraints(
            maxHeight: AleraTokens.agentChatPlanPreviewMaxHeight,
          ),
          decoration: BoxDecoration(
            color: AleraTokens.surface,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.border),
          ),
          padding: const EdgeInsets.all(AleraTokens.space8),
          child: SingleChildScrollView(
            child: AgentChatMarkdown(data: widget.preview),
          ),
        ),
    ],
  );
}

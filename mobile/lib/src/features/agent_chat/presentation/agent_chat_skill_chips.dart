import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/design_system/chips/alera_inline_chip.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:flutter/material.dart';

/// A sent message's text, with the skills it invoked drawn as chips, as T3
/// Code's timeline does. Without a mention of a known skill it stays the
/// selectable text it always was.
class const AgentChatUserBubbleText({
  super.key,
  required final String text,
  required final bool collapsed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final skills =
        AgentChatScope.maybeOf(context)?.skills ??
        const <AgentChatProviderSkill>[];
    final segments = agentChatSkillTextSegments(text, skills);
    final chips = segments.length > 1 || segments.first.skill != null;
    if (!chips) {
      return collapsed
          ? Text(
              text,
              maxLines: agentChatMessageCollapseLines,
              overflow: .ellipsis,
            )
          : SelectableText(text);
    }
    final rich = Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final segment in segments)
            switch (segment.skill) {
              final skill? => AleraInlineChip.span(
                label: skill.label,
                icon: AleraIcons.skill,
                tooltip: '\$${skill.name}',
              ),
              null => TextSpan(text: segment.text),
            },
        ],
      ),
      maxLines: collapsed ? agentChatMessageCollapseLines : null,
      overflow: collapsed ? .ellipsis : null,
    );
    return collapsed ? rich : SelectionArea(child: rich);
  }
}

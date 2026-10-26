import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The composer's text, with each finished mention of a known skill painted
/// as a token. It stays plain text, so the caret, selection and the prompt
/// that is sent are exactly what was typed; T3 Code collapses the mention
/// into a chip instead, which a Flutter text field cannot hold.
class AgentChatSkillTextController extends TextEditingController {
  AgentChatSkillTextController.fromValue(super.value) : super.fromValue();

  List<AgentChatProviderSkill> _skills = const <AgentChatProviderSkill>[];

  List<AgentChatProviderSkill> get skills => _skills;

  set skills(List<AgentChatProviderSkill> skills) {
    if (identical(skills, _skills)) return;
    _skills = skills;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // An input method's composing underline wins while it is composing.
    if (_skills.isEmpty ||
        (withComposing && value.isComposingRangeValid) ||
        !text.contains(RegExp(r'\p{Sc}', unicode: true))) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return TextSpan(
      style: style,
      children: <InlineSpan>[
        for (final segment in agentChatSkillTextSegments(
          text,
          _skills,
          typing: true,
        ))
          TextSpan(
            text: segment.text,
            style: segment.skill == null
                ? null
                : const TextStyle(
                    color: AleraTokens.foreground,
                    fontWeight: FontWeight.w600,
                    backgroundColor: AleraTokens.accentSubtle,
                  ),
          ),
      ],
    );
  }
}

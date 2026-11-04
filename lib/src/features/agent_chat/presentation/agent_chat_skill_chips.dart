import 'package:alera/src/design_system/chips/alera_inline_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/markdown/alera_markdown_view.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/widgets.dart';

/// The skills of the chat on screen, so the messages under it can draw the
/// skills they invoked as chips, as T3 Code's timeline does. Absent, or
/// before the runtime answers, mentions stay text.
class const AgentChatSkillsScope({
  super.key,
  required final List<AgentChatProviderSkill> skills,
  required super.child,
}) extends InheritedWidget {
  static List<AgentChatProviderSkill> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AgentChatSkillsScope>()
          ?.skills ??
      const <AgentChatProviderSkill>[];

  @override
  bool updateShouldNotify(AgentChatSkillsScope oldWidget) =>
      !_sameSkills(oldWidget.skills, skills);
}

bool _sameSkills(
  List<AgentChatProviderSkill> left,
  List<AgentChatProviderSkill> right,
) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

InlineSpan agentChatSkillChip(AgentChatProviderSkill skill) =>
    AleraInlineChip.span(
      label: skill.label,
      icon: AleraIcons.skill,
      tooltip: '\$${skill.name}',
    );

/// Unicode `Sc` spelled out: the Markdown renderer re-matches each token
/// without the `unicode` flag, where `\p{Sc}` would not mean a currency
/// sigil. Astral sigils are written as their UTF-16 surrogate pairs.
const String _currencySigil =
    r'(?:[$\u00A2-\u00A5\u058F\u060B\u07FE\u07FF\u09F2\u09F3\u09FB\u0AF1'
    r'\u0BF9\u0E3F\u17DB\u20A0-\u20C0\uA838\uFDFC\uFE69\uFF04\uFFE0\uFFE1'
    r'\uFFE5\uFFE6]|\uD807[\uDFDD-\uDFE0]|\uD838\uDEFF|\uD83B\uDCB0)';

/// The Markdown token that draws mentions of [skills] as chips, or `null`
/// without skills. It follows the shared mention grammar, so `$5` and a
/// name inside a word stay text.
AleraMarkdownInlineToken? agentChatSkillMarkdownToken(
  List<AgentChatProviderSkill> skills,
) {
  if (skills.isEmpty) return null;
  final byName = <String, AgentChatProviderSkill>{
    for (final skill in skills) skill.name: skill,
  };
  final names = byName.keys.toList()
    ..sort((left, right) => right.length.compareTo(left.length));
  return AleraMarkdownInlineToken(
    pattern: RegExp(
      '(?<![^\\s])$_currencySigil'
      r'(?![0-9][0-9_]*(?:[kKmMbBtT]|[eE][0-9]+)?(?:\s|$))'
      '(${names.map(RegExp.escape).join('|')})'
      r'(?=\s|$)',
    ),
    build: (context, match, style) => switch (byName[match.group(1)]) {
      final skill? => agentChatSkillChip(skill),
      null => TextSpan(text: match.group(0), style: style),
    },
  );
}

/// [text] as spans with the mentions of [skills] drawn as chips.
List<InlineSpan> agentChatSkillTextSpans(
  String text,
  List<AgentChatProviderSkill> skills,
) => <InlineSpan>[
  for (final segment in agentChatSkillTextSegments(text, skills))
    switch (segment.skill) {
      final skill? => agentChatSkillChip(skill),
      null => TextSpan(text: segment.text),
    },
];

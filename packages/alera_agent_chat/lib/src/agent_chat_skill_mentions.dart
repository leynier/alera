import 'package:alera_agent_chat/src/agent_chat_provider_skill.dart';

/// T3 Code's `SKILL_MENTION_SOURCE`: a currency sigil at the start or after
/// white space, then a name of ASCII letters, digits, `:`, `_` and `-` that
/// starts with a letter or digit and contains a letter. Amounts such as `$25`,
/// `$2_000`, `$5k` and `$1e6` never match. The runtime adapters share the same
/// grammar, so a chip the composer shows is a skill the agent receives.
const String _mentionSource =
    r'(^|\s)\p{Sc}(?![0-9][0-9_]*(?:[kKmMbBtT]|[eE][0-9]+)?(?:\s|$))'
    r'(?=[a-zA-Z0-9:_-]*[a-zA-Z])([a-zA-Z0-9][a-zA-Z0-9:_-]*)';

/// A mention that ends at white space or the end of the text, as sent
/// prompts and timeline messages read them.
final RegExp _settledMention = RegExp(
  '$_mentionSource(?=\\s|\$)',
  unicode: true,
);

/// A mention followed by white space: what the composer turns into a chip,
/// so a name is not decorated while it is still being typed.
final RegExp _typedMention = RegExp('$_mentionSource(?=\\s)', unicode: true);

/// One mention of a known skill in a text. [start] is the sigil's offset and
/// [end] the offset just after the name, both in UTF-16 code units.
final class const AgentChatSkillMention({
  required final int start,
  required final int end,
  required final AgentChatProviderSkill skill,
}) {
  @override
  bool operator ==(Object other) =>
      other is AgentChatSkillMention &&
      other.start == start &&
      other.end == end &&
      other.skill == skill;

  @override
  int get hashCode => Object.hash(start, end, skill);
}

/// T3 Code's `matchInlineSkills`: the mentions in [text] whose name is one
/// of [skills], in order. With [typing], a mention must be followed by white
/// space, as the composer's chips require.
List<AgentChatSkillMention> agentChatSkillMentions(
  String text,
  Iterable<AgentChatProviderSkill> skills, {
  bool typing = false,
}) {
  final byName = <String, AgentChatProviderSkill>{
    for (final skill in skills) skill.name: skill,
  };
  if (byName.isEmpty || text.isEmpty) {
    return const <AgentChatSkillMention>[];
  }
  return <AgentChatSkillMention>[
    for (final match in (typing ? _typedMention : _settledMention).allMatches(
      text,
    ))
      if (byName[match.group(2)] case final skill?)
        AgentChatSkillMention(
          start: match.start + (match.group(1)?.length ?? 0),
          end: match.end,
          skill: skill,
        ),
  ];
}

/// A run of text that either is a mention of a known skill or is not.
final class const AgentChatSkillTextSegment({
  required final String text,
  final AgentChatProviderSkill? skill,
}) {
  @override
  bool operator ==(Object other) =>
      other is AgentChatSkillTextSegment &&
      other.text == text &&
      other.skill == skill;

  @override
  int get hashCode => Object.hash(text, skill);
}

/// [text] split into plain runs and skill mentions, for rendering chips.
List<AgentChatSkillTextSegment> agentChatSkillTextSegments(
  String text,
  Iterable<AgentChatProviderSkill> skills, {
  bool typing = false,
}) {
  final mentions = agentChatSkillMentions(text, skills, typing: typing);
  if (mentions.isEmpty) {
    return <AgentChatSkillTextSegment>[AgentChatSkillTextSegment(text: text)];
  }
  final segments = <AgentChatSkillTextSegment>[];
  var cursor = 0;
  for (final mention in mentions) {
    if (mention.start > cursor) {
      segments.add(
        AgentChatSkillTextSegment(text: text.substring(cursor, mention.start)),
      );
    }
    segments.add(
      AgentChatSkillTextSegment(
        text: text.substring(mention.start, mention.end),
        skill: mention.skill,
      ),
    );
    cursor = mention.end;
  }
  if (cursor < text.length) {
    segments.add(AgentChatSkillTextSegment(text: text.substring(cursor)));
  }
  return segments;
}

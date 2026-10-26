import 'package:alera_agent_chat/src/agent_chat_provider_skill.dart';
import 'package:alera_agent_chat/src/agent_chat_search_ranking.dart';

/// T3 Code's `scoreProviderSkill`: the name ranks first, then the label,
/// the short description, the description and the scope. [query] must be
/// normalized.
int? agentChatScoreProviderSkill(AgentChatProviderSkill skill, String query) {
  final scores = <int?>[
    agentChatScoreQueryMatch(
      value: skill.name.toLowerCase(),
      query: query,
      exactBase: 0,
      prefixBase: 2,
      boundaryBase: 4,
      includesBase: 6,
      fuzzyBase: 100,
      boundaryMarkers: const <String>['-', '_', '/'],
    ),
    agentChatScoreQueryMatch(
      value: skill.label.toLowerCase(),
      query: query,
      exactBase: 1,
      prefixBase: 3,
      boundaryBase: 5,
      includesBase: 7,
      fuzzyBase: 110,
    ),
    agentChatScoreQueryMatch(
      value: skill.shortDescription?.toLowerCase() ?? '',
      query: query,
      exactBase: 20,
      prefixBase: 22,
      boundaryBase: 24,
      includesBase: 26,
    ),
    agentChatScoreQueryMatch(
      value: skill.description?.toLowerCase() ?? '',
      query: query,
      exactBase: 30,
      prefixBase: 32,
      boundaryBase: 34,
      includesBase: 36,
    ),
    agentChatScoreQueryMatch(
      value: skill.scope?.toLowerCase() ?? '',
      query: query,
      exactBase: 40,
      prefixBase: 42,
      includesBase: 44,
    ),
  ].nonNulls;
  if (scores.isEmpty) return null;
  return scores.reduce((best, score) => score < best ? score : best);
}

final RegExp _leadingSigils = RegExp(r'^\p{Sc}+', unicode: true);

/// T3 Code's `searchProviderSkills`: the skills a person can pick that match
/// [query], best first, or all of them in list order without a query.
List<AgentChatProviderSkill> agentChatSearchProviderSkills(
  Iterable<AgentChatProviderSkill> skills,
  String query, {
  int? limit,
}) {
  final invocable = agentChatDedupeSkillsByName(<AgentChatProviderSkill>[
    for (final skill in skills)
      if (skill.isUserInvocable) skill,
  ]);
  final normalized = agentChatNormalizeSearchQuery(
    query,
    trimLeading: _leadingSigils,
  );
  if (normalized.isEmpty) {
    return limit == null ? invocable : invocable.take(limit).toList();
  }
  final ranked = <AgentChatRankedResult<AgentChatProviderSkill>>[];
  for (final skill in invocable) {
    final score = agentChatScoreProviderSkill(skill, normalized);
    if (score == null) continue;
    agentChatInsertRanked(
      ranked,
      AgentChatRankedResult<AgentChatProviderSkill>(
        item: skill,
        score: score,
        tieBreaker: '${skill.label.toLowerCase()}\u0000${skill.name}',
      ),
      limit: limit,
    );
  }
  return <AgentChatProviderSkill>[for (final entry in ranked) entry.item];
}

import 'dart:collection';

import 'package:alera/src/features/codex_chat/domain/codex_timeline_cell.dart';

List<CodexTimelineCell> codexTimelineCellsWithoutClaimedMatches(
  List<CodexTimelineCell> candidates,
  List<CodexTimelineCell> replacements, {
  bool Function(CodexTimelineCell candidate)? replacedByExactHistory,
}) {
  final index = _CodexTimelineIdentityIndex(candidates);
  final exactMatches = List<bool>.filled(replacements.length, false);
  if (replacedByExactHistory != null) {
    for (
      var replacementIndex = 0;
      replacementIndex < replacements.length;
      replacementIndex++
    ) {
      exactMatches[replacementIndex] = index.hasExact(
        replacements[replacementIndex],
      );
    }
    index.claimWhere(replacedByExactHistory);
  } else {
    for (
      var replacementIndex = 0;
      replacementIndex < replacements.length;
      replacementIndex++
    ) {
      exactMatches[replacementIndex] = index.claimExact(
        replacements[replacementIndex],
      );
    }
  }
  final semanticStart = replacements.length > _timelineTextMatchWindow
      ? replacements.length - _timelineTextMatchWindow
      : 0;
  for (
    var indexValue = semanticStart;
    indexValue < replacements.length;
    indexValue++
  ) {
    if (!exactMatches[indexValue]) {
      index.claimText(replacements[indexValue]);
    }
  }
  return <CodexTimelineCell>[
    for (var cellIndex = 0; cellIndex < candidates.length; cellIndex++)
      if (!index.claimed.contains(cellIndex)) candidates[cellIndex],
  ];
}

final class _CodexTimelineIdentityIndex {
  _CodexTimelineIdentityIndex(this.cells) {
    for (var index = 0; index < cells.length; index++) {
      final cell = cells[index];
      _add(ids, cell.id, index);
      _addIfPresent(canonicalIds, _canonicalItemId(cell), index);
    }
  }

  static const _textMatchWindow = _timelineTextMatchWindow;

  final List<CodexTimelineCell> cells;
  final Set<int> claimed = <int>{};
  final Map<String, ListQueue<int>> ids = <String, ListQueue<int>>{};
  final Map<String, ListQueue<int>> canonicalIds = <String, ListQueue<int>>{};
  final Map<int, String> normalizedTexts = <int, String>{};
  final Map<String, ListQueue<int>> semanticKeys = <String, ListQueue<int>>{};
  final Map<String, ListQueue<int>> prefixBuckets = <String, ListQueue<int>>{};
  final Map<String, ListQueue<int>> legacySemanticKeys =
      <String, ListQueue<int>>{};
  final Map<String, ListQueue<int>> explicitSemanticKeys =
      <String, ListQueue<int>>{};
  final Map<String, ListQueue<int>> legacyPrefixBuckets =
      <String, ListQueue<int>>{};
  final Map<String, ListQueue<int>> explicitPrefixBuckets =
      <String, ListQueue<int>>{};
  bool _textIndexBuilt = false;

  void _ensureTextIndex() {
    if (_textIndexBuilt) return;
    _textIndexBuilt = true;
    final start = cells.length > _textMatchWindow
        ? cells.length - _textMatchWindow
        : 0;
    for (var index = start; index < cells.length; index++) {
      final cell = cells[index];
      if (!_isAgentText(cell)) continue;
      final normalizedText = _normalize(cell.markdownText);
      normalizedTexts[index] = normalizedText;
      _addIfPresent(semanticKeys, _semanticKey(cell, normalizedText), index);
      _addIfPresent(prefixBuckets, _agentBucketKey(cell), index);
      final wildcardKey = _phaseAgnosticSemanticKey(cell, normalizedText);
      final wildcardBucket = _agentBaseBucketKey(cell);
      if (_streamPhase(cell) == null) {
        _addIfPresent(legacySemanticKeys, wildcardKey, index);
        _addIfPresent(legacyPrefixBuckets, wildcardBucket, index);
      } else {
        _addIfPresent(explicitSemanticKeys, wildcardKey, index);
        _addIfPresent(explicitPrefixBuckets, wildcardBucket, index);
      }
    }
  }

  void claimWhere(bool Function(CodexTimelineCell candidate) predicate) {
    for (var index = 0; index < cells.length; index++) {
      if (!claimed.contains(index) && predicate(cells[index])) {
        claimed.add(index);
      }
    }
  }

  bool hasExact(CodexTimelineCell replacement) {
    if (ids[replacement.id]?.isNotEmpty == true) return true;
    final canonicalId = _canonicalItemId(replacement);
    return canonicalId != null && canonicalIds[canonicalId]?.isNotEmpty == true;
  }

  bool claimExact(CodexTimelineCell replacement) {
    if (_claimFrom(ids[replacement.id])) return true;
    final canonicalId = _canonicalItemId(replacement);
    return canonicalId != null && _claimFrom(canonicalIds[canonicalId]);
  }

  void claimText(CodexTimelineCell replacement) {
    if (!_isAgentText(replacement)) return;
    _ensureTextIndex();
    final replacementText = _normalize(replacement.markdownText);
    final semanticKey = _semanticKey(replacement, replacementText);
    if (semanticKey != null && _claimFrom(semanticKeys[semanticKey])) return;
    final wildcardKey = _phaseAgnosticSemanticKey(replacement, replacementText);
    final replacementPhase = _streamPhase(replacement);
    final wildcardSemantic = replacementPhase == null
        ? explicitSemanticKeys[wildcardKey]
        : legacySemanticKeys[wildcardKey];
    final wildcardMatched = replacementPhase == null
        ? _claimUniqueFrom(wildcardSemantic)
        : _claimFrom(wildcardSemantic);
    if (wildcardMatched) return;
    final bucketKey = _agentBucketKey(replacement);
    final wildcardBucketKey = _agentBaseBucketKey(replacement);
    final wildcardBucket = replacementPhase == null
        ? explicitPrefixBuckets[wildcardBucketKey]
        : legacyPrefixBuckets[wildcardBucketKey];
    _claimUniquePrefix(
      <ListQueue<int>?>[prefixBuckets[bucketKey], wildcardBucket],
      replacement,
      replacementText,
    );
  }

  bool _claimUniquePrefix(
    List<ListQueue<int>?> buckets,
    CodexTimelineCell replacement,
    String replacementText,
  ) {
    if (replacementText.isEmpty) return false;
    int? matchedIndex;
    for (final bucket in buckets) {
      if (bucket == null) continue;
      for (final candidateIndex in bucket) {
        if (claimed.contains(candidateIndex)) continue;
        final candidate = cells[candidateIndex];
        final candidateText = normalizedTexts[candidateIndex] ?? '';
        if (!(candidate.isStreaming || replacement.isStreaming) ||
            candidateText == replacementText ||
            !(candidateText.startsWith(replacementText) ||
                replacementText.startsWith(candidateText))) {
          continue;
        }
        if (matchedIndex != null && matchedIndex != candidateIndex) {
          return false;
        }
        matchedIndex = candidateIndex;
      }
    }
    return matchedIndex != null && claimed.add(matchedIndex);
  }

  bool _claimFrom(ListQueue<int>? queue) {
    if (queue == null) return false;
    while (queue.isNotEmpty) {
      final candidate = queue.removeFirst();
      if (claimed.add(candidate)) return true;
    }
    return false;
  }

  bool _claimUniqueFrom(ListQueue<int>? queue) {
    if (queue == null) return false;
    int? matchedIndex;
    for (final candidateIndex in queue) {
      if (claimed.contains(candidateIndex)) continue;
      if (matchedIndex != null) return false;
      matchedIndex = candidateIndex;
    }
    return matchedIndex != null && claimed.add(matchedIndex);
  }

  static void _add(Map<String, ListQueue<int>> target, String key, int index) {
    target.putIfAbsent(key, ListQueue<int>.new).add(index);
  }

  static void _addIfPresent(
    Map<String, ListQueue<int>> target,
    String? key,
    int index,
  ) {
    if (key != null) _add(target, key, index);
  }
}

const _timelineTextMatchWindow = 64;

String? _semanticKey(CodexTimelineCell cell, String normalizedText) {
  final bucket = _agentBucketKey(cell);
  return bucket == null || normalizedText.isEmpty
      ? null
      : '$bucket\u0000$normalizedText';
}

String? _phaseAgnosticSemanticKey(
  CodexTimelineCell cell,
  String normalizedText,
) {
  final bucket = _agentBaseBucketKey(cell);
  return bucket == null || normalizedText.isEmpty
      ? null
      : '$bucket\u0000$normalizedText';
}

String? _agentBucketKey(CodexTimelineCell cell) {
  final bucket = _agentBaseBucketKey(cell);
  return bucket == null ? null : '$bucket\u0000${_streamPhase(cell) ?? ''}';
}

String? _agentBaseBucketKey(CodexTimelineCell cell) =>
    !_isAgentText(cell) || cell.turnId == null
    ? null
    : '${cell.turnId}\u0000${cell.kind.name}';

String? _streamPhase(CodexTimelineCell cell) {
  final phase = cell.metadata['streamPhase'];
  return phase is String && phase.trim().isNotEmpty ? phase : null;
}

String? _canonicalItemId(CodexTimelineCell cell) {
  if (cell.itemId?.isNotEmpty == true) return cell.itemId;
  return cell.id.startsWith('item-') && cell.id.length > 5
      ? cell.id.substring(5)
      : null;
}

bool _isAgentText(CodexTimelineCell cell) => switch (cell.kind) {
  CodexTimelineKind.assistantMessage || CodexTimelineKind.progressText => true,
  _ => false,
};

String _normalize(String? value) =>
    value?.trim().split(RegExp(r'\s+')).join(' ') ?? '';

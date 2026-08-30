part of 'mobile_codex_controller.dart';

const _mobileAgentTextKinds = <String>{'assistantMessage', 'progressText'};

List<MobileCodexTimelineCell> _mobileCellsWithoutClaimedMatches(
  List<MobileCodexTimelineCell> candidates,
  List<MobileCodexTimelineCell> replacements, {
  bool Function(MobileCodexTimelineCell candidate)? replacedByExactHistory,
}) {
  final index = _MobileCodexTimelineIdentityIndex(candidates);
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
  final semanticStart = replacements.length > _mobileTimelineTextMatchWindow
      ? replacements.length - _mobileTimelineTextMatchWindow
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
  return <MobileCodexTimelineCell>[
    for (var cellIndex = 0; cellIndex < candidates.length; cellIndex++)
      if (!index.claimed.contains(cellIndex)) candidates[cellIndex],
  ];
}

final class _MobileCodexTimelineIdentityIndex(
  final List<MobileCodexTimelineCell> cells,
) {
  this {
    for (var index = 0; index < cells.length; index++) {
      final cell = cells[index];
      _add(ids, cell.id, index);
      _addIfPresent(canonicalIds, _mobileCanonicalItemId(cell), index);
    }
  }

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
    final start = cells.length > _mobileTimelineTextMatchWindow
        ? cells.length - _mobileTimelineTextMatchWindow
        : 0;
    for (var index = start; index < cells.length; index++) {
      final cell = cells[index];
      if (!_mobileAgentTextKinds.contains(cell.kind)) continue;
      final normalizedText = _normalizeMobileTimelineText(cell.markdownText);
      normalizedTexts[index] = normalizedText;
      _addIfPresent(
        semanticKeys,
        _mobileSemanticKey(cell, normalizedText),
        index,
      );
      _addIfPresent(prefixBuckets, _mobileAgentBucketKey(cell), index);
      final wildcardKey = _mobilePhaseAgnosticSemanticKey(cell, normalizedText);
      final wildcardBucket = _mobileAgentBaseBucketKey(cell);
      if (_mobileStreamPhase(cell) == null) {
        _addIfPresent(legacySemanticKeys, wildcardKey, index);
        _addIfPresent(legacyPrefixBuckets, wildcardBucket, index);
      } else {
        _addIfPresent(explicitSemanticKeys, wildcardKey, index);
        _addIfPresent(explicitPrefixBuckets, wildcardBucket, index);
      }
    }
  }

  void claimWhere(bool Function(MobileCodexTimelineCell candidate) predicate) {
    for (var index = 0; index < cells.length; index++) {
      if (!claimed.contains(index) && predicate(cells[index])) {
        claimed.add(index);
      }
    }
  }

  bool hasExact(MobileCodexTimelineCell replacement) {
    if (ids[replacement.id]?.isNotEmpty == true) return true;
    final canonicalId = _mobileCanonicalItemId(replacement);
    return canonicalId != null && canonicalIds[canonicalId]?.isNotEmpty == true;
  }

  bool claimExact(MobileCodexTimelineCell replacement) {
    if (_claimFrom(ids[replacement.id])) return true;
    final canonicalId = _mobileCanonicalItemId(replacement);
    return canonicalId != null && _claimFrom(canonicalIds[canonicalId]);
  }

  void claimText(MobileCodexTimelineCell replacement) {
    if (!_mobileAgentTextKinds.contains(replacement.kind)) return;
    _ensureTextIndex();
    final replacementText = _normalizeMobileTimelineText(
      replacement.markdownText,
    );
    final semanticKey = _mobileSemanticKey(replacement, replacementText);
    if (semanticKey != null && _claimFrom(semanticKeys[semanticKey])) return;
    final wildcardKey = _mobilePhaseAgnosticSemanticKey(
      replacement,
      replacementText,
    );
    final replacementPhase = _mobileStreamPhase(replacement);
    final wildcardSemantic = replacementPhase == null
        ? explicitSemanticKeys[wildcardKey]
        : legacySemanticKeys[wildcardKey];
    final wildcardMatched = replacementPhase == null
        ? _claimUniqueFrom(wildcardSemantic)
        : _claimFrom(wildcardSemantic);
    if (wildcardMatched) return;
    final bucketKey = _mobileAgentBucketKey(replacement);
    final wildcardBucketKey = _mobileAgentBaseBucketKey(replacement);
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
    MobileCodexTimelineCell replacement,
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

const _mobileTimelineTextMatchWindow = 64;

String? _mobileSemanticKey(
  MobileCodexTimelineCell cell,
  String normalizedText,
) {
  final bucket = _mobileAgentBucketKey(cell);
  return bucket == null || normalizedText.isEmpty
      ? null
      : '$bucket\u0000$normalizedText';
}

String? _mobilePhaseAgnosticSemanticKey(
  MobileCodexTimelineCell cell,
  String normalizedText,
) {
  final bucket = _mobileAgentBaseBucketKey(cell);
  return bucket == null || normalizedText.isEmpty
      ? null
      : '$bucket\u0000$normalizedText';
}

String? _mobileAgentBucketKey(MobileCodexTimelineCell cell) {
  final bucket = _mobileAgentBaseBucketKey(cell);
  return bucket == null
      ? null
      : '$bucket\u0000${_mobileStreamPhase(cell) ?? ''}';
}

String? _mobileAgentBaseBucketKey(MobileCodexTimelineCell cell) =>
    !_mobileAgentTextKinds.contains(cell.kind) || cell.turnId == null
    ? null
    : '${cell.turnId}\u0000${cell.kind}';

String? _mobileStreamPhase(MobileCodexTimelineCell cell) {
  final phase = cell.metadata['streamPhase'];
  return phase is String && phase.trim().isNotEmpty ? phase : null;
}

String? _mobileCanonicalItemId(MobileCodexTimelineCell cell) {
  if (cell.itemId?.isNotEmpty == true) return cell.itemId;
  return cell.id.startsWith('item-') && cell.id.length > 5
      ? cell.id.substring(5)
      : null;
}

String _normalizeMobileTimelineText(String? value) =>
    value?.trim().split(RegExp(r'\s+')).join(' ') ?? '';

/// T3 Code's `searchRanking.ts`, which orders its composer menus: lower
/// scores rank first, and an exact match beats a prefix, a word boundary, a
/// substring and finally a fuzzy subsequence.
library;

import 'dart:math' as math;

/// T3 Code's `normalizeSearchQuery`: trimmed and lower case, with
/// [trimLeading] removed from the start.
String agentChatNormalizeSearchQuery(String input, {Pattern? trimLeading}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  final stripped = trimLeading == null
      ? trimmed
      : trimmed.replaceFirst(trimLeading, '');
  return stripped.toLowerCase();
}

int? _subsequenceScore(String value, String query, bool ignorePosition) {
  if (query.isEmpty) return 0;
  var queryIndex = 0;
  var firstMatch = -1;
  var previousMatch = -1;
  var gapPenalty = 0;
  for (var index = 0; index < value.length; index += 1) {
    if (value[index] != query[queryIndex]) continue;
    if (firstMatch == -1) firstMatch = index;
    if (previousMatch != -1) gapPenalty += index - previousMatch - 1;
    previousMatch = index;
    queryIndex += 1;
    if (queryIndex == query.length) {
      final spanPenalty = index - firstMatch + 1 - query.length;
      if (ignorePosition) return gapPenalty * 3 + spanPenalty;
      final lengthPenalty = math.min(64, value.length - query.length);
      return firstMatch * 2 + gapPenalty * 3 + spanPenalty + lengthPenalty;
    }
  }
  return null;
}

int? _boundaryIndex(String value, String query, List<String> markers) {
  int? best;
  for (final marker in markers) {
    final index = value.indexOf('$marker$query');
    if (index == -1) continue;
    final matchIndex = index + marker.length;
    if (best == null || matchIndex < best) best = matchIndex;
  }
  return best;
}

/// T3 Code's `scoreQueryMatch`. [value] and [query] must already be trimmed
/// and lower case.
int? agentChatScoreQueryMatch({
  required String value,
  required String query,
  required int exactBase,
  int? prefixBase,
  int? boundaryBase,
  int? includesBase,
  int? fuzzyBase,
  List<String> boundaryMarkers = const <String>[' ', '-', '_', '/'],
  bool ignorePosition = false,
}) {
  if (value.isEmpty || query.isEmpty) return null;
  final penalty = ignorePosition
      ? 0
      : math.min(64, math.max(0, value.length - query.length));
  if (value == query) return exactBase;
  if (prefixBase != null && value.startsWith(query)) {
    return prefixBase + penalty;
  }
  if (boundaryBase != null) {
    final index = _boundaryIndex(value, query, boundaryMarkers);
    if (index != null) {
      return boundaryBase + (ignorePosition ? 0 : index * 2) + penalty;
    }
  }
  if (includesBase != null) {
    final index = value.indexOf(query);
    if (index != -1) {
      return includesBase + (ignorePosition ? 0 : index * 2) + penalty;
    }
  }
  if (fuzzyBase != null) {
    final fuzzy = _subsequenceScore(value, query, ignorePosition);
    if (fuzzy != null) return fuzzyBase + fuzzy;
  }
  return null;
}

/// An item with its score and the text that breaks a tie.
final class const AgentChatRankedResult<T>({
  required final T item,
  required final int score,
  required final String tieBreaker,
});

int _primaryClass(int unit) {
  if (unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D) return 0;
  if (_symbols.contains(String.fromCharCode(unit))) return 1;
  if (unit >= 0x30 && unit <= 0x39) return 2;
  if ((unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)) {
    return 3;
  }
  return 4;
}

const String _symbols = '_-,;:!?.\'"()[]{}@*/\\&#%`^+<=>|~\$';

int _primaryWeight(int unit) {
  final kind = _primaryClass(unit);
  if (kind == 1) return _symbols.indexOf(String.fromCharCode(unit));
  if (kind == 3 && unit <= 0x5A) return unit + 0x20;
  return unit;
}

/// `localeCompare` under the root collation, reduced to the ASCII text menu
/// names contain: punctuation, then digits, then letters without case, and
/// lower case first at the first case difference. The Rust adapters sort
/// skill lists with the same rule (`compare_skill_names`).
int agentChatLocaleCompare(String left, String right) {
  final length = math.min(left.length, right.length);
  for (var index = 0; index < length; index += 1) {
    final a = left.codeUnitAt(index);
    final b = right.codeUnitAt(index);
    final byClass = _primaryClass(a).compareTo(_primaryClass(b));
    if (byClass != 0) return byClass;
    final byWeight = _primaryWeight(a).compareTo(_primaryWeight(b));
    if (byWeight != 0) return byWeight;
  }
  final byLength = left.length.compareTo(right.length);
  if (byLength != 0) return byLength;
  for (var index = 0; index < length; index += 1) {
    final upperA = _isUpper(left.codeUnitAt(index));
    final upperB = _isUpper(right.codeUnitAt(index));
    if (upperA != upperB) return upperA ? 1 : -1;
  }
  return left.compareTo(right);
}

bool _isUpper(int unit) => unit >= 0x41 && unit <= 0x5A;

int _compareRanked<T>(
  AgentChatRankedResult<T> left,
  AgentChatRankedResult<T> right,
) {
  final byScore = left.score.compareTo(right.score);
  if (byScore != 0) return byScore;
  return agentChatLocaleCompare(left.tieBreaker, right.tieBreaker);
}

/// T3 Code's `insertRankedSearchResult`: keeps [ranked] sorted and at most
/// [limit] long, a later equal entry after an earlier one.
void agentChatInsertRanked<T>(
  List<AgentChatRankedResult<T>> ranked,
  AgentChatRankedResult<T> candidate, {
  int? limit,
}) {
  if (limit != null && limit <= 0) return;
  var low = 0;
  var high = ranked.length;
  while (low < high) {
    final middle = low + (high - low) ~/ 2;
    if (_compareRanked(candidate, ranked[middle]) < 0) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  if (limit == null || ranked.length < limit) {
    ranked.insert(low, candidate);
    return;
  }
  if (low >= limit) return;
  ranked
    ..insert(low, candidate)
    ..removeLast();
}

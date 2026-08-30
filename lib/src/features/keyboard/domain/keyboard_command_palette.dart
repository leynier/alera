import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';

class const KeyboardCommandMatch({
  required final KeybindingDefinition definition,
  required final int score,
});

const int defaultKeyboardCommandPaletteResultLimit = 50;

/// Filters the central keyboard registry for Command Palette.
List<KeyboardCommandMatch> filterKeyboardCommandPalette(
  String query, {
  List<KeybindingDefinition> definitions = keybindingDefinitions,
  int limit = defaultKeyboardCommandPaletteResultLimit,
}) {
  if (limit <= 0) {
    return const <KeyboardCommandMatch>[];
  }
  final normalizedQuery = query.trim().toLowerCase();
  final matches = <KeyboardCommandMatch>[];
  for (final definition in definitions) {
    final score = _keyboardCommandScore(definition, normalizedQuery);
    if (score != null) {
      matches.add(KeyboardCommandMatch(definition: definition, score: score));
    }
  }
  matches.sort((left, right) {
    final scoreComparison = right.score.compareTo(left.score);
    if (scoreComparison != 0) {
      return scoreComparison;
    }
    final labelComparison = left.definition.label.toLowerCase().compareTo(
      right.definition.label.toLowerCase(),
    );
    if (labelComparison != 0) {
      return labelComparison;
    }
    return left.definition.id.name.compareTo(right.definition.id.name);
  });
  return matches.take(limit).toList(growable: false);
}

int? _keyboardCommandScore(KeybindingDefinition definition, String query) {
  if (query.isEmpty) {
    return 0;
  }
  final label = definition.label.toLowerCase();
  if (label == query) {
    return 100000;
  }
  if (label.startsWith(query)) {
    return 90000;
  }

  var bestKeywordScore = 0;
  for (final keyword in definition.searchKeywords) {
    final normalizedKeyword = keyword.toLowerCase();
    if (normalizedKeyword == query) {
      bestKeywordScore = bestKeywordScore < 85000 ? 85000 : bestKeywordScore;
    } else if (normalizedKeyword.startsWith(query)) {
      bestKeywordScore = bestKeywordScore < 80000 ? 80000 : bestKeywordScore;
    } else if (normalizedKeyword.contains(query)) {
      bestKeywordScore = bestKeywordScore < 70000 ? 70000 : bestKeywordScore;
    }
  }
  if (bestKeywordScore > 0) {
    return bestKeywordScore;
  }

  final searchableText = <String>[
    label,
    definition.description.toLowerCase(),
    definition.group.label.toLowerCase(),
  ].join(' ');
  if (searchableText.contains(query)) {
    return 60000 - searchableText.indexOf(query).clamp(0, 999).toInt();
  }
  final fuzzyScore = _keyboardCommandFuzzyScore(searchableText, query);
  return fuzzyScore == null ? null : 1000 + fuzzyScore;
}

int? _keyboardCommandFuzzyScore(String candidate, String query) {
  var candidateIndex = 0;
  var previousMatchIndex = -1;
  var score = 0;
  for (final queryCharacter in query.codeUnits) {
    final matchIndex = candidate.indexOf(
      String.fromCharCode(queryCharacter),
      candidateIndex,
    );
    if (matchIndex < 0) {
      return null;
    }
    score += matchIndex == candidateIndex ? 20 : 0;
    if (previousMatchIndex >= 0) {
      score -= (matchIndex - previousMatchIndex - 1) * 5;
    }
    previousMatchIndex = matchIndex;
    candidateIndex = matchIndex + 1;
  }
  return score;
}

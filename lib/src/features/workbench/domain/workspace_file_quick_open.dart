/// A ranked Quick Open candidate for a workspace file.
class WorkspaceFileQuickOpenMatch {
  const WorkspaceFileQuickOpenMatch({
    required this.relativePath,
    required this.score,
  });

  final String relativePath;
  final int score;
}

const int defaultWorkspaceFileQuickOpenResultLimit = 50;
const int defaultWorkspaceFileQuickOpenEnumerationLimit = 10000;

/// Returns workspace-relative file paths ranked for a Quick Open query.
///
/// Exact paths, file-name prefixes, and path-segment matches are preferred
/// before a looser fuzzy subsequence match. Ties are ordered by path so a
/// changing filesystem traversal order cannot move the selected row.
List<WorkspaceFileQuickOpenMatch> rankWorkspaceFileQuickOpenMatches(
  Iterable<String> relativePaths,
  String query, {
  int limit = defaultWorkspaceFileQuickOpenResultLimit,
}) {
  if (limit <= 0) {
    return const <WorkspaceFileQuickOpenMatch>[];
  }
  final normalizedQuery = query.trim().toLowerCase();
  final matches = <WorkspaceFileQuickOpenMatch>[];
  for (final relativePath in relativePaths) {
    final score = _workspaceFileQuickOpenScore(relativePath, normalizedQuery);
    if (score != null) {
      matches.add(
        WorkspaceFileQuickOpenMatch(relativePath: relativePath, score: score),
      );
    }
  }
  matches.sort((left, right) {
    final scoreComparison = right.score.compareTo(left.score);
    if (scoreComparison != 0) {
      return scoreComparison;
    }
    final normalizedPathComparison = left.relativePath.toLowerCase().compareTo(
      right.relativePath.toLowerCase(),
    );
    if (normalizedPathComparison != 0) {
      return normalizedPathComparison;
    }
    return left.relativePath.compareTo(right.relativePath);
  });
  return matches.take(limit).toList(growable: false);
}

int? _workspaceFileQuickOpenScore(String relativePath, String query) {
  if (query.isEmpty) {
    return 0;
  }
  final candidate = relativePath.toLowerCase();
  final segments = candidate.split(RegExp(r'[/\\]'));
  final fileName = segments.last;
  if (candidate == query) {
    return 100000;
  }
  final exactSegmentIndex = segments.indexOf(query);
  if (exactSegmentIndex >= 0) {
    return 90000 - exactSegmentIndex;
  }
  if (candidate.startsWith(query)) {
    return 80000;
  }
  final prefixSegmentIndex = segments.indexWhere(
    (segment) => segment.startsWith(query),
  );
  if (prefixSegmentIndex >= 0) {
    return 70000 - prefixSegmentIndex;
  }
  final containsIndex = candidate.indexOf(query);
  if (containsIndex >= 0) {
    return 60000 - containsIndex;
  }
  final fuzzyScore = _fuzzySubsequenceScore(candidate, query);
  if (fuzzyScore == null) {
    return null;
  }
  return 1000 + fuzzyScore + (fileName.startsWith(query) ? 100 : 0);
}

int? _fuzzySubsequenceScore(String candidate, String query) {
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
    final isSegmentStart =
        matchIndex == 0 ||
        _isPathSeparator(candidate.codeUnitAt(matchIndex - 1));
    score += isSegmentStart ? 100 : 0;
    score += matchIndex == candidateIndex ? 20 : 0;
    if (previousMatchIndex >= 0) {
      score -= (matchIndex - previousMatchIndex - 1) * 5;
    }
    previousMatchIndex = matchIndex;
    candidateIndex = matchIndex + 1;
  }
  return score;
}

bool _isPathSeparator(int codeUnit) => codeUnit == 0x2f || codeUnit == 0x5c;

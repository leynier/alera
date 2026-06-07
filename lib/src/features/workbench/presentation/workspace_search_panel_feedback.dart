part of 'workspace_search_panel.dart';

@visibleForTesting
bool workspaceSearchCanReplaceFile(WorkspaceSearchState state) {
  return state.hasQuery &&
      !state.loading &&
      !state.replacing &&
      (state.result?.totalMatches ?? 0) > 0 &&
      state.result?.truncated != true;
}

@visibleForTesting
String? workspaceSearchReplaceConflictMessage(
  native.WorkspaceReplaceResult result,
) {
  if (result.conflicts.isEmpty) {
    return null;
  }
  final skipped = result.conflicts
      .map((conflict) => conflict.relativePath)
      .toSet()
      .length;
  final first = result.conflicts.first;
  final firstReason = '${first.relativePath}: ${first.reason}';
  final skippedFiles = skipped == 1 ? '1 file' : '$skipped files';
  if (result.matchesReplaced > 0) {
    final matchWord = result.matchesReplaced == 1 ? 'match' : 'matches';
    return 'Replaced ${result.matchesReplaced} $matchWord. $skippedFiles skipped. $firstReason';
  }
  return 'Replace skipped $skippedFiles. $firstReason';
}

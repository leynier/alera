import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_text_search_controller.g.dart';

class const WorkspaceTextSearchState({
  final String query = '',
  final bool caseSensitive = false,
  final bool wholeWord = false,
  final bool useRegex = false,
  final String includePattern = '',
  final String excludePattern = '',
  final MobileWorkspaceSearchResult? result,
  final Object? error,
  final bool searching = false,
});

@riverpod
class WorkspaceTextSearchController extends _$WorkspaceTextSearchController {
  Timer? _debounce;
  var _generation = 0;

  @override
  WorkspaceTextSearchState build(String hostId, String workspaceId) {
    ref.onDispose(() => _debounce?.cancel());
    return const WorkspaceTextSearchState();
  }

  void setQuery(String query) {
    state = WorkspaceTextSearchState(
      query: query,
      caseSensitive: state.caseSensitive,
      wholeWord: state.wholeWord,
      useRegex: state.useRegex,
      includePattern: state.includePattern,
      excludePattern: state.excludePattern,
    );
    _schedule();
  }

  void toggleCaseSensitive() {
    state = WorkspaceTextSearchState(
      query: state.query,
      caseSensitive: !state.caseSensitive,
      wholeWord: state.wholeWord,
      useRegex: state.useRegex,
      includePattern: state.includePattern,
      excludePattern: state.excludePattern,
      result: state.result,
    );
    _schedule();
  }

  void toggleWholeWord() {
    state = WorkspaceTextSearchState(
      query: state.query,
      caseSensitive: state.caseSensitive,
      wholeWord: !state.wholeWord,
      useRegex: state.useRegex,
      includePattern: state.includePattern,
      excludePattern: state.excludePattern,
      result: state.result,
    );
    _schedule();
  }

  void toggleUseRegex() {
    state = WorkspaceTextSearchState(
      query: state.query,
      caseSensitive: state.caseSensitive,
      wholeWord: state.wholeWord,
      useRegex: !state.useRegex,
      includePattern: state.includePattern,
      excludePattern: state.excludePattern,
      result: state.result,
    );
    _schedule();
  }

  void setIncludePattern(String value) {
    state = WorkspaceTextSearchState(
      query: state.query,
      caseSensitive: state.caseSensitive,
      wholeWord: state.wholeWord,
      useRegex: state.useRegex,
      includePattern: value,
      excludePattern: state.excludePattern,
      result: state.result,
    );
    _schedule();
  }

  void setExcludePattern(String value) {
    state = WorkspaceTextSearchState(
      query: state.query,
      caseSensitive: state.caseSensitive,
      wholeWord: state.wholeWord,
      useRegex: state.useRegex,
      includePattern: state.includePattern,
      excludePattern: value,
      result: state.result,
    );
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), runNow);
  }

  Future<void> runNow() async {
    final query = state.query.trim();
    if (query.isEmpty) {
      state = WorkspaceTextSearchState(
        query: state.query,
        caseSensitive: state.caseSensitive,
        wholeWord: state.wholeWord,
        useRegex: state.useRegex,
        includePattern: state.includePattern,
        excludePattern: state.excludePattern,
      );
      return;
    }
    final generation = ++_generation;
    state = WorkspaceTextSearchState(
      query: state.query,
      caseSensitive: state.caseSensitive,
      wholeWord: state.wholeWord,
      useRegex: state.useRegex,
      includePattern: state.includePattern,
      excludePattern: state.excludePattern,
      searching: true,
    );
    final client = await ref.read(workspaceClientProvider(hostId).future);
    if (generation != _generation) {
      return;
    }
    if (client case final MobileWorkspacePanelsClient panels
        when panels.supportsWorkspaceSearch) {
      try {
        final result = await panels.searchWorkspace(
          workspaceId: workspaceId,
          query: query,
          caseSensitive: state.caseSensitive,
          wholeWord: state.wholeWord,
          useRegex: state.useRegex,
          includePattern: state.includePattern,
          excludePattern: state.excludePattern,
        );
        if (generation != _generation) {
          return;
        }
        state = WorkspaceTextSearchState(
          query: state.query,
          caseSensitive: state.caseSensitive,
          wholeWord: state.wholeWord,
          useRegex: state.useRegex,
          includePattern: state.includePattern,
          excludePattern: state.excludePattern,
          result: result,
        );
      } on Object catch (error) {
        if (generation != _generation) {
          return;
        }
        state = WorkspaceTextSearchState(
          query: state.query,
          caseSensitive: state.caseSensitive,
          wholeWord: state.wholeWord,
          useRegex: state.useRegex,
          includePattern: state.includePattern,
          excludePattern: state.excludePattern,
          error: error,
        );
      }
      return;
    }
    state = WorkspaceTextSearchState(
      query: state.query,
      caseSensitive: state.caseSensitive,
      wholeWord: state.wholeWord,
      useRegex: state.useRegex,
      includePattern: state.includePattern,
      excludePattern: state.excludePattern,
      error: 'Update the paired Alera runtime to search the workspace.',
    );
  }
}

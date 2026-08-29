import 'dart:async';

import 'package:alera/src/features/workbench/application/retired_workspace_invalidation.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_search_service.dart';
import 'package:alera/src/rust/api/workspace_search.dart' as native;
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_search_controller.g.dart';

const int _workspaceSearchMaxResults = 2000;
const Duration _workspaceSearchDebounce = Duration(milliseconds: 250);
final p.Context _workspaceSearchPathContext = p.Context(style: p.Style.posix);

String workspaceSearchDirectoryNodeKey(String relativePath) {
  return 'dir:$relativePath';
}

String workspaceSearchFileNodeKey(String relativePath) {
  return 'file:$relativePath';
}

Set<String> workspaceSearchCollapsibleNodeKeys(
  native.WorkspaceSearchResult? result, {
  required bool viewAsTree,
}) {
  if (result == null) {
    return const <String>{};
  }
  final keys = <String>{};
  for (final file in result.files) {
    if (viewAsTree) {
      for (final directory in workspaceSearchDirectoryPaths(
        file.relativePath,
      )) {
        keys.add(workspaceSearchDirectoryNodeKey(directory));
      }
    }
    keys.add(workspaceSearchFileNodeKey(file.relativePath));
  }
  return keys;
}

List<String> workspaceSearchDirectoryPaths(String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/');
  final segments = _workspaceSearchPathContext
      .split(normalized)
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.length <= 1) {
    return const <String>[];
  }
  final paths = <String>[];
  final current = <String>[];
  for (final segment in segments.take(segments.length - 1)) {
    current.add(segment);
    paths.add(_workspaceSearchPathContext.joinAll(current));
  }
  return paths;
}

class WorkspaceSearchState {
  const WorkspaceSearchState({
    this.query = '',
    this.replacement = '',
    this.includePattern = '',
    this.excludePattern = '',
    this.caseSensitive = false,
    this.wholeWord = false,
    this.useRegex = false,
    this.preserveCase = false,
    this.includeIgnored = false,
    this.loading = false,
    this.replacing = false,
    this.viewAsTree = false,
    this.error,
    this.result,
    this.collapsedResultNodeKeys = const <String>{},
  });

  final String query;
  final String replacement;
  final String includePattern;
  final String excludePattern;
  final bool caseSensitive;
  final bool wholeWord;
  final bool useRegex;
  final bool preserveCase;
  final bool includeIgnored;
  final bool loading;
  final bool replacing;
  final bool viewAsTree;
  final String? error;
  final native.WorkspaceSearchResult? result;
  final Set<String> collapsedResultNodeKeys;

  Set<String> get collapsedFilePaths => collapsedResultNodeKeys;

  bool get hasQuery => query.isNotEmpty;

  bool get hasReplacement => replacement.isNotEmpty;

  WorkspaceSearchState copyWith({
    String? query,
    String? replacement,
    String? includePattern,
    String? excludePattern,
    bool? caseSensitive,
    bool? wholeWord,
    bool? useRegex,
    bool? preserveCase,
    bool? includeIgnored,
    bool? loading,
    bool? replacing,
    bool? viewAsTree,
    Object? error = _sentinel,
    Object? result = _sentinel,
    Set<String>? collapsedResultNodeKeys,
  }) {
    return WorkspaceSearchState(
      query: query ?? this.query,
      replacement: replacement ?? this.replacement,
      includePattern: includePattern ?? this.includePattern,
      excludePattern: excludePattern ?? this.excludePattern,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      wholeWord: wholeWord ?? this.wholeWord,
      useRegex: useRegex ?? this.useRegex,
      preserveCase: preserveCase ?? this.preserveCase,
      includeIgnored: includeIgnored ?? this.includeIgnored,
      loading: loading ?? this.loading,
      replacing: replacing ?? this.replacing,
      viewAsTree: viewAsTree ?? this.viewAsTree,
      error: identical(error, _sentinel) ? this.error : error as String?,
      result: identical(result, _sentinel)
          ? this.result
          : result as native.WorkspaceSearchResult?,
      collapsedResultNodeKeys:
          collapsedResultNodeKeys ?? this.collapsedResultNodeKeys,
    );
  }
}

const Object _sentinel = Object();

class WorkspaceSearchDirtyFilesException implements Exception {
  const WorkspaceSearchDirtyFilesException(this.paths);

  final List<String> paths;

  @override
  String toString() => 'Unsaved files: ${paths.join(', ')}';
}

@Riverpod(keepAlive: true)
class WorkspaceSearchController extends _$WorkspaceSearchController {
  Timer? _debounce;
  int _requestGeneration = 0;
  String? _activeRequestId;
  WorkspaceSearchService? _searchService;

  @override
  WorkspaceSearchState build(String workspaceId) {
    invalidateWhenWorkspaceRetired(ref, workspaceId);
    _searchService = ref.read(workspaceSearchServiceProvider);
    ref.onDispose(() {
      _debounce?.cancel();
      _cancelActiveSearch();
      _requestGeneration += 1;
    });
    return const WorkspaceSearchState();
  }

  void setQuery(String workspacePath, String value) {
    if (state.query == value) {
      return;
    }
    _applySearchInputChange(workspacePath, state.copyWith(query: value));
  }

  void setReplacement(String workspacePath, String value) {
    if (state.replacement == value) {
      return;
    }
    _applySearchInputChange(workspacePath, state.copyWith(replacement: value));
  }

  void setIncludePattern(String workspacePath, String value) {
    if (state.includePattern == value) {
      return;
    }
    _applySearchInputChange(
      workspacePath,
      state.copyWith(includePattern: value),
    );
  }

  void setExcludePattern(String workspacePath, String value) {
    if (state.excludePattern == value) {
      return;
    }
    _applySearchInputChange(
      workspacePath,
      state.copyWith(excludePattern: value),
    );
  }

  void toggleCaseSensitive(String workspacePath) {
    _applySearchInputChange(
      workspacePath,
      state.copyWith(caseSensitive: !state.caseSensitive),
    );
  }

  void toggleWholeWord(String workspacePath) {
    _applySearchInputChange(
      workspacePath,
      state.copyWith(wholeWord: !state.wholeWord),
    );
  }

  void toggleUseRegex(String workspacePath) {
    _applySearchInputChange(
      workspacePath,
      state.copyWith(useRegex: !state.useRegex),
    );
  }

  void togglePreserveCase(String workspacePath) {
    _applySearchInputChange(
      workspacePath,
      state.copyWith(preserveCase: !state.preserveCase),
    );
  }

  void toggleIncludeIgnored(String workspacePath) {
    _applySearchInputChange(
      workspacePath,
      state.copyWith(includeIgnored: !state.includeIgnored),
    );
  }

  void toggleResultNodeCollapsed(String nodeKey) {
    final next = Set<String>.from(state.collapsedResultNodeKeys);
    if (!next.add(nodeKey)) {
      next.remove(nodeKey);
    }
    state = state.copyWith(collapsedResultNodeKeys: next);
  }

  void toggleFileCollapsed(String relativePath) {
    toggleResultNodeCollapsed(workspaceSearchFileNodeKey(relativePath));
  }

  void toggleAllResultsCollapsed() {
    final keys = workspaceSearchCollapsibleNodeKeys(
      state.result,
      viewAsTree: state.viewAsTree,
    );
    if (keys.isEmpty) {
      return;
    }
    final allCollapsed = keys.every(state.collapsedResultNodeKeys.contains);
    state = state.copyWith(
      collapsedResultNodeKeys: allCollapsed ? const <String>{} : keys,
    );
  }

  void toggleAllFilesCollapsed() {
    toggleAllResultsCollapsed();
  }

  void toggleViewAsTree() {
    state = state.copyWith(viewAsTree: !state.viewAsTree);
  }

  void clearSearchResults() {
    _debounce?.cancel();
    _cancelActiveSearch();
    _requestGeneration += 1;
    state = state.copyWith(
      query: '',
      replacement: '',
      includePattern: '',
      excludePattern: '',
      loading: false,
      error: null,
      result: null,
      collapsedResultNodeKeys: const <String>{},
    );
  }

  Future<void> searchNow(String workspacePath) async {
    _debounce?.cancel();
    _cancelActiveSearch();
    final query = state.query;
    final generation = ++_requestGeneration;
    if (query.isEmpty) {
      state = state.copyWith(loading: false, error: null, result: null);
      return;
    }
    final requestId = '$workspacePath:${identityHashCode(this)}:$generation';
    _activeRequestId = requestId;
    state = state.copyWith(loading: true, error: null);
    try {
      final searchOptions = _searchOptions(workspacePath);
      final result = state.hasReplacement
          ? (await _service.previewReplace(
              options: native.WorkspaceReplaceOptions(
                search: searchOptions,
                replacement: state.replacement,
                preserveCase: state.preserveCase,
              ),
              requestId: requestId,
            )).result
          : await _service.search(options: searchOptions, requestId: requestId);
      if (generation != _requestGeneration) {
        return;
      }
      state = state.copyWith(loading: false, result: result, error: null);
    } catch (error) {
      if (generation != _requestGeneration) {
        return;
      }
      state = state.copyWith(
        loading: false,
        result: null,
        error: _messageFor(error),
      );
    } finally {
      if (_activeRequestId == requestId) {
        _activeRequestId = null;
      }
    }
  }

  Future<native.WorkspaceReplaceResult> replaceMatches({
    required String workspacePath,
    required Iterable<String> matchIds,
    required EditorSessionRegistry editorSessions,
  }) async {
    final result = state.result;
    if (result == null) {
      const message = 'Run search before replacing.';
      state = state.copyWith(error: message);
      throw StateError(message);
    }
    final selectedMatchIds = matchIds.toSet();
    if (selectedMatchIds.isEmpty && result.truncated) {
      const message = 'Replace all is unavailable while results are truncated.';
      state = state.copyWith(error: message);
      throw StateError(message);
    }
    final affectedFiles = _affectedFiles(selectedMatchIds);
    final dirtyPaths = editorSessions.dirtyPathsFor(
      workspacePath: workspacePath,
      relativePaths: affectedFiles.map((file) => file.relativePath),
    );
    if (dirtyPaths.isNotEmpty) {
      state = state.copyWith(error: _dirtyMessage(dirtyPaths));
      throw WorkspaceSearchDirtyFilesException(dirtyPaths);
    }
    state = state.copyWith(replacing: true, error: null);
    try {
      final result = await _service.replaceMatches(
        request: native.WorkspaceReplaceRequest(
          options: native.WorkspaceReplaceOptions(
            search: _searchOptions(workspacePath),
            replacement: state.replacement,
            preserveCase: state.preserveCase,
          ),
          matchIds: selectedMatchIds.toList(growable: false),
          expectedFiles: <native.WorkspaceReplaceFileExpectation>[
            for (final file in affectedFiles)
              native.WorkspaceReplaceFileExpectation(
                relativePath: file.relativePath,
                contentToken: file.contentToken,
              ),
          ],
        ),
      );
      editorSessions.reloadCleanFiles(
        workspacePath: workspacePath,
        relativePaths: affectedFiles.map((file) => file.relativePath),
      );
      state = state.copyWith(replacing: false);
      await searchNow(workspacePath);
      return result;
    } catch (error) {
      state = state.copyWith(replacing: false, error: _messageFor(error));
      rethrow;
    }
  }

  WorkspaceSearchService get _service => _searchService!;

  native.WorkspaceSearchOptions _searchOptions(String workspacePath) {
    return native.WorkspaceSearchOptions(
      workspacePath: workspacePath,
      query: state.query,
      caseSensitive: state.caseSensitive,
      wholeWord: state.wholeWord,
      useRegex: state.useRegex,
      includePattern: _nullablePattern(state.includePattern),
      excludePattern: _nullablePattern(state.excludePattern),
      includeIgnored: state.includeIgnored,
      maxResults: _workspaceSearchMaxResults,
    );
  }

  String? _nullablePattern(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _scheduleSearch(String workspacePath) {
    _debounce?.cancel();
    if (!state.hasQuery) {
      state = state.copyWith(loading: false, error: null, result: null);
      return;
    }
    _debounce = Timer(
      _workspaceSearchDebounce,
      () => unawaited(searchNow(workspacePath)),
    );
  }

  void _applySearchInputChange(
    String workspacePath,
    WorkspaceSearchState next,
  ) {
    _cancelActiveSearch();
    _requestGeneration += 1;
    state = next.copyWith(
      loading: next.hasQuery,
      error: null,
      result: null,
      collapsedResultNodeKeys: const <String>{},
    );
    _scheduleSearch(workspacePath);
  }

  void _cancelActiveSearch() {
    final requestId = _activeRequestId;
    if (requestId == null) {
      return;
    }
    _activeRequestId = null;
    unawaited(_ignoreCancellationFailure(requestId));
  }

  Future<void> _ignoreCancellationFailure(String requestId) async {
    try {
      await _service.cancel(requestId: requestId);
    } on Object {
      // Cancellation is best effort because stale generations are also ignored.
    }
  }

  List<native.WorkspaceSearchFileResult> _affectedFiles(Set<String> matchIds) {
    final result = state.result;
    if (result == null) {
      return const <native.WorkspaceSearchFileResult>[];
    }
    if (matchIds.isEmpty) {
      return result.files;
    }
    return <native.WorkspaceSearchFileResult>[
      for (final file in result.files)
        if (file.matches.any((match) => matchIds.contains(match.id))) file,
    ];
  }

  String _messageFor(Object error) {
    if (error is native.WorkspaceSearchError) {
      return error.context;
    }
    if (error is WorkspaceSearchDirtyFilesException) {
      return _dirtyMessage(error.paths);
    }
    return 'Search failed: $error';
  }

  String _dirtyMessage(List<String> paths) {
    if (paths.length == 1) {
      return 'Save or discard ${paths.single} before replacing.';
    }
    return 'Save or discard ${paths.length} open files before replacing.';
  }
}

import 'dart:async';

import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_search_service.dart';
import 'package:alera/src/rust/api/workspace_search.dart' as native;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_search_controller.g.dart';

const int _workspaceSearchMaxResults = 2000;
const Duration _workspaceSearchDebounce = Duration(milliseconds: 250);

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
    this.loading = false,
    this.replacing = false,
    this.error,
    this.result,
    this.collapsedFilePaths = const <String>{},
  });

  final String query;
  final String replacement;
  final String includePattern;
  final String excludePattern;
  final bool caseSensitive;
  final bool wholeWord;
  final bool useRegex;
  final bool preserveCase;
  final bool loading;
  final bool replacing;
  final String? error;
  final native.WorkspaceSearchResult? result;
  final Set<String> collapsedFilePaths;

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
    bool? loading,
    bool? replacing,
    Object? error = _sentinel,
    Object? result = _sentinel,
    Set<String>? collapsedFilePaths,
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
      loading: loading ?? this.loading,
      replacing: replacing ?? this.replacing,
      error: identical(error, _sentinel) ? this.error : error as String?,
      result: identical(result, _sentinel)
          ? this.result
          : result as native.WorkspaceSearchResult?,
      collapsedFilePaths: collapsedFilePaths ?? this.collapsedFilePaths,
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

  @override
  WorkspaceSearchState build(String workspaceId) {
    ref.onDispose(() {
      _debounce?.cancel();
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

  void toggleFileCollapsed(String relativePath) {
    final next = Set<String>.from(state.collapsedFilePaths);
    if (!next.add(relativePath)) {
      next.remove(relativePath);
    }
    state = state.copyWith(collapsedFilePaths: next);
  }

  Future<void> searchNow(String workspacePath) async {
    _debounce?.cancel();
    final query = state.query;
    final generation = ++_requestGeneration;
    if (query.isEmpty) {
      state = state.copyWith(loading: false, error: null, result: null);
      return;
    }
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
            )).result
          : await _service.search(options: searchOptions);
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

  WorkspaceSearchService get _service =>
      ref.read(workspaceSearchServiceProvider);

  native.WorkspaceSearchOptions _searchOptions(String workspacePath) {
    return native.WorkspaceSearchOptions(
      workspacePath: workspacePath,
      query: state.query,
      caseSensitive: state.caseSensitive,
      wholeWord: state.wholeWord,
      useRegex: state.useRegex,
      includePattern: _nullablePattern(state.includePattern),
      excludePattern: _nullablePattern(state.excludePattern),
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
    _requestGeneration += 1;
    state = next.copyWith(loading: next.hasQuery, error: null, result: null);
    _scheduleSearch(workspacePath);
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
